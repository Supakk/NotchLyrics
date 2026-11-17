import AppKit
import SwiftUI

/// Extracts accent colors from album artwork (implementation lives in NotchuMotion).
enum ColorExtractor {
    static func gradient(from image: NSImage?) -> [Color] { ArtworkPalette.gradient(from: image) }
}
