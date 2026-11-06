import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() throws {
        // This renderer runs outside an app bundle; register the same artwork
        // that Xcode copies into the app and widget resource bundles.
        for name in ["CodexIcon", "ClaudeCodeIcon"] {
            let asset = URL(fileURLWithPath: "Shared/Resources/\(name).png")
            NSImage(contentsOf: asset)?.setName(NSImage.Name(name))
        }
        let snapshot = try CommandLine.arguments.count > 2
            ? JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
            : SnapshotStore.load()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, width, height) in [("small", 164.0, 164.0), ("medium", 344.0, 164.0), ("large", 344.0, 344.0)] {
            let content = Group {
                if name == "medium" {
                    UsageBands(snapshot: snapshot)
                } else {
                    UsageDashboard(snapshot: snapshot, compact: name == "small", dense: true,
                        vertical: true, maxWindows: name == "small" ? 1 : 4)
                        .padding(16)
                }
            }.frame(width: width, height: height, alignment: .topLeading)
                .background(Color(red: 0.065, green: 0.078, blue: 0.082))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: output.appendingPathComponent("\(name).png"))
        }
        print("Rendered all three widget layouts.")
    }
}
