import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('usage', Path(__file__).parents[1] / 'Scripts/usage.py')
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)

class UsageTests(unittest.TestCase):
    def test_codex_prefers_codex_bucket(self):
        result = usage.parse_codex({'rateLimits': {'primary': {'usedPercent': 99}},
            'rateLimitsByLimitId': {'codex': {'primary': {
                'usedPercent': 22, 'windowDurationMins': 300, 'resetsAt': 1780000000}}}})
        self.assertEqual(result[0]['usedPercent'], 22)
        self.assertEqual(result[0]['label'], '5 hours')
        self.assertIn('+00:00', result[0]['resetsAt'])

    def test_missing_is_not_zero(self):
        with self.assertRaises(usage.UsageError):
            usage.parse_claude({'five_hour': None, 'seven_day': {}})
        self.assertIsNone(usage.window('Weekly', None))
        self.assertIsNone(usage.window('Weekly', float('nan')))

    def test_allowlist_excludes_credentials_and_unknown_fields(self):
        payload = {'five_hour': {'utilization': 12.5, 'resets_at': '2026-10-03T15:00:00Z',
                                 'accessToken': 'SECRET'}, 'accessToken': 'SECRET'}
        result = usage.parse_claude(payload)
        self.assertNotIn('SECRET', json.dumps(result))
        self.assertEqual(set(result[0]), {'label', 'usedPercent', 'resetsAt'})
        self.assertEqual(result[0]['usedPercent'], 12.5)

    def test_error_strings_cannot_leak(self):
        def failing():
            raise RuntimeError('Bearer SECRET')
        result = usage.collect('Claude Code', failing)
        self.assertNotIn('SECRET', json.dumps(result))
        self.assertEqual(result['windows'], [])
        self.assertIsNone(result['updatedAt'])

    def test_clamping_and_null_reset(self):
        self.assertEqual(usage.window('Session', 123)['usedPercent'], 100)
        self.assertEqual(usage.window('Session', -12)['usedPercent'], 0)
        self.assertIsNone(usage.window('Session', 0, 'invalid')['resetsAt'])

    def test_redirects_never_forward_credentials(self):
        self.assertIsNone(usage.NoRedirect().redirect_request(None, None, 302, None, None, None))

    def test_credit_count_and_earliest_expiry(self):
        result = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 2, 'credits': [
            {'id': 'PRIVATE_ID', 'status': 'available', 'expiresAt': 1792000000},
            {'status': 'available', 'expiresAt': 1791000000},
            {'status': 'consumed', 'expiresAt': 1790000000}]}})
        self.assertEqual(result['availableCount'], 2)
        self.assertTrue(result['detailsComplete'])
        self.assertEqual(result['nextExpiresAt'], usage.window('x', 0, 1791000000)['resetsAt'])
        self.assertNotIn('PRIVATE_ID', json.dumps(result))
        self.assertEqual(result['expiresAt'], [usage.window('x', 0, stamp)['resetsAt']
                                               for stamp in [1791000000, 1792000000]])

    def test_credit_expiries_keep_duplicates_and_exclude_invalid(self):
        result = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 4, 'credits': [
            {'status': 'available', 'expiresAt': 1791000000},
            {'status': 'available', 'expiresAt': 1791000000},
            {'status': 'available', 'expiresAt': float('nan')},
            {'status': 'available', 'expiresAt': True}]}})
        self.assertEqual(len(result['expiresAt']), 2)
        self.assertEqual(result['expiresAt'][0], result['expiresAt'][1])

    def test_credit_details_can_be_incomplete(self):
        result = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 5,
            'credits': [{'status': 'available', 'expiresAt': 1791000000}]}})
        self.assertEqual(result['availableCount'], 5)
        self.assertFalse(result['detailsComplete'])
        missing = usage.parse_reset_credits({})
        self.assertIsNone(missing['availableCount'])
        count_only = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 3, 'credits': None}})
        self.assertIsNone(count_only['nextExpiresAt'])

    def test_zero_credits_and_nonexpiring_credits(self):
        zero = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 0, 'credits': []}})
        self.assertEqual(zero['availableCount'], 0)
        self.assertIsNone(zero['nextExpiresAt'])
        nonexpiring = usage.parse_reset_credits({'rateLimitResetCredits': {'availableCount': 1,
            'credits': [{'status': 'available', 'expiresAt': None}]}})
        self.assertTrue(nonexpiring['detailsComplete'])
        self.assertIsNone(nonexpiring['nextExpiresAt'])

if __name__ == '__main__':
    unittest.main()
