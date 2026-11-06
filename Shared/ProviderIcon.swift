import AppKit
import SwiftUI

/// Original product artwork, bundled with both the app and the widget.
struct ProviderIcon: View {
    let provider: ProviderUsage
    var size: CGFloat = 18

    private var artwork: NSImage {
        let name = provider.name == "Codex" ? "CodexIcon" : "ClaudeCodeIcon"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // The standalone preview registers these names without an app bundle.
        return NSImage(named: NSImage.Name(name)) ?? NSImage()
    }

    var body: some View {
        Image(nsImage: artwork)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
