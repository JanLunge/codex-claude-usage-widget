#!/usr/bin/python3
"""Read account usage. Only allowlisted usage fields may leave this process."""
import concurrent.futures
import datetime as dt
import json
import math
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import time
import urllib.error
import urllib.request

class UsageError(Exception):
    pass

def timestamp():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def window(label, percent, reset=None):
    if not isinstance(percent, (int, float)) or isinstance(percent, bool) or not math.isfinite(percent):
        return None
    if isinstance(reset, (int, float)):
        reset = dt.datetime.fromtimestamp(reset, dt.timezone.utc).isoformat()
    if isinstance(reset, str):
        try:
            reset = dt.datetime.fromisoformat(reset.replace('Z', '+00:00')).isoformat()
        except ValueError:
            reset = None
    else:
        reset = None
    return {'label': label, 'usedPercent': max(0, min(100, percent)), 'resetsAt': reset}

def parse_codex(result):
    buckets = result.get('rateLimitsByLimitId') or {}
    rate = buckets.get('codex') or result.get('rateLimits') or {}
    windows = []
    for key, fallback in [('primary', 'Session'), ('secondary', 'Weekly')]:
        value = rate.get(key)
        if not isinstance(value, dict):
            continue
        minutes = value.get('windowDurationMins')
        label = ('5 hours' if minutes == 300 else 'Weekly' if minutes == 10080
                 else f'{minutes // 60:g} hours' if isinstance(minutes, int) and minutes >= 60
                 else f'{minutes} minutes' if isinstance(minutes, int) else fallback)
        parsed = window(label, value.get('usedPercent'), value.get('resetsAt'))
        if parsed:
            windows.append(parsed)
    if not windows:
        raise UsageError('No subscription limits returned. Sign in to Codex with ChatGPT.')
    return windows

def parse_claude(result):
    windows = []
    for key, label in [('five_hour', '5 hours'), ('seven_day', 'Weekly'),
                       ('seven_day_sonnet', 'Sonnet weekly'), ('seven_day_opus', 'Opus weekly')]:
        value = result.get(key)
        if isinstance(value, dict):
            parsed = window(label, value.get('utilization'), value.get('resets_at'))
            if parsed:
                windows.append(parsed)
    if not windows:
        raise UsageError('No Claude subscription limits returned.')
    return windows

def parse_reset_credits(result):
    summary = result.get('rateLimitResetCredits')
    if not isinstance(summary, dict):
        return {'availableCount': None, 'nextExpiresAt': None, 'detailsComplete': False, 'expiresAt': []}
    count = summary.get('availableCount')
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        count = None
    rows = summary.get('credits')
    expiries = []
    available = []
    if isinstance(rows, list):
        available = [row for row in rows if isinstance(row, dict) and row.get('status') == 'available']
        for row in available:
            expiry = row.get('expiresAt')
            if isinstance(expiry, (int, float)) and not isinstance(expiry, bool) and math.isfinite(expiry):
                try:
                    expiries.append(dt.datetime.fromtimestamp(expiry, dt.timezone.utc))
                except (ValueError, OverflowError, OSError):
                    pass
    complete = count is not None and isinstance(rows, list) and len(available) >= count
    return {'availableCount': count,
            'nextExpiresAt': min(expiries).isoformat() if expiries and count != 0 else None,
            'detailsComplete': complete,
            'expiresAt': [expiry.isoformat() for expiry in sorted(expiries)] if count != 0 else []}

def codex_binary():
    for path in [shutil.which('codex'), '/opt/homebrew/bin/codex', '/usr/local/bin/codex',
                 '/Applications/Codex.app/Contents/Resources/codex']:
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    raise UsageError('Codex CLI was not found. Install or open Codex first.')

def fetch_codex():
    # The official client handles its own login; never open its auth store here.
    process = subprocess.Popen([codex_binary(), 'app-server', '--listen', 'stdio://',
                                '-c', 'mcp_servers={}', '-c', 'analytics.enabled=false'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    pending = b''
    deadline = time.monotonic() + 35
    def send(message):
        process.stdin.write((json.dumps(message) + '\n').encode())
    def response(identifier):
        nonlocal pending
        while time.monotonic() < deadline:
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                try:
                    item = json.loads(line)
                except (ValueError, UnicodeError):
                    continue
                if item.get('id') == identifier:
                    if 'error' in item:
                        # Never forward a server error body: it is not allowlisted.
                        raise UsageError('Codex could not read usage. Check its sign-in and connection.')
                    return item.get('result', {})
            if selector.select(timeout=max(0, min(1, deadline - time.monotonic()))):
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                pending += chunk
                if len(pending) > 2_000_000:
                    raise UsageError('Unexpected Codex response.')
        raise UsageError('Codex usage request timed out.')
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {
            'name': 'local_usage_widget', 'title': 'Usage Widget', 'version': '1.0.0'}}})
        response(1)
        send({'method': 'initialized'})
        send({'id': 2, 'method': 'account/rateLimits/read'})
        result = response(2)
        return {'windows': parse_codex(result), 'resetCredits': parse_reset_credits(result)}
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()

def claude_access_token(payload, keychain=False):
    try:
        credentials = json.loads(payload)
    except (ValueError, UnicodeError):
        if not keychain:
            raise
        # security -w emits hex when stored bytes include non-printable characters.
        # Decode in memory; neither representation may be logged or cached.
        credentials = json.loads(bytes.fromhex(payload.decode('ascii').strip()))
    oauth = credentials.get('claudeAiOauth') if isinstance(credentials, dict) else None
    token = oauth.get('accessToken') if isinstance(oauth, dict) else None
    return token if isinstance(token, str) and token.strip() else None

def claude_token():
    config = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude'))).expanduser()
    services = ['Claude Code-credentials']
    # Claude namespaces custom configuration directories by their path hash.
    if 'CLAUDE_CONFIG_DIR' in os.environ:
        import hashlib
        services.insert(0, 'Claude Code-credentials-' + hashlib.sha256(str(config).encode()).hexdigest()[:8])
    credential_error = None
    for service in services:
        result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', service, '-w'],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
        if result.returncode == 0:
            try:
                token = claude_access_token(result.stdout, keychain=True)
                if token:
                    return token
                credential_error = 'Claude credentials contain no OAuth token. Sign in to Claude Code with your Claude account.'
            except (ValueError, UnicodeError):
                credential_error = 'Claude credentials could not be decoded. Update Usage Widget or sign in again through Claude Code.'
    # Linux-style credentials are also supported, without logging their contents.
    try:
        token = claude_access_token((config / '.credentials.json').read_bytes())
        if token:
            return token
        credential_error = 'Claude credentials contain no OAuth token. Sign in to Claude Code with your Claude account.'
    except OSError:
        pass
    except (ValueError, UnicodeError):
        credential_error = credential_error or 'Claude credentials could not be decoded. Update Usage Widget or sign in again through Claude Code.'
    raise UsageError(credential_error or 'Claude Code credentials unavailable. Check Keychain access and Claude Code sign-in.')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        # Do not forward a bearer token to a redirected host.
        return None

def fetch_claude():
    token = claude_token()
    request = urllib.request.Request('https://api.anthropic.com/api/oauth/usage', headers={
        'Authorization': 'Bearer ' + token, 'anthropic-beta': 'oauth-2025-04-20',
        'Accept': 'application/json', 'User-Agent': 'LocalUsageWidget/1.0'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
            return parse_claude(json.load(response))
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise UsageError('Claude sign-in expired or unavailable. Reopen Claude Code.') from None
        if error.code == 429:
            raise UsageError('Claude usage is rate limited. Retry later.') from None
        raise UsageError('Claude usage service is unavailable.') from None
    except (urllib.error.URLError, TimeoutError):
        raise UsageError('Cannot reach Claude usage. Check your connection.') from None

def collect(name, fetch):
    try:
        data = fetch()
        result = {'name': name, 'windows': data['windows'] if isinstance(data, dict) else data,
                  'updatedAt': timestamp(), 'error': None}
        if isinstance(data, dict):
            result['resetCredits'] = data.get('resetCredits')
        return result
    except UsageError as error:
        return {'name': name, 'windows': [], 'updatedAt': None, 'error': str(error)}
    except Exception:
        # Credentials, response bodies, and exception strings never reach stdout.
        return {'name': name, 'windows': [], 'updatedAt': None,
                'error': 'Usage unavailable. Check the local client sign-in.'}

def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        codex = pool.submit(collect, 'Codex', fetch_codex)
        claude = pool.submit(collect, 'Claude Code', fetch_claude)
        result = {'fetchedAt': timestamp(), 'providers': [codex.result(), claude.result()]}
    print(json.dumps(result, allow_nan=False))

if __name__ == '__main__':
    main()
