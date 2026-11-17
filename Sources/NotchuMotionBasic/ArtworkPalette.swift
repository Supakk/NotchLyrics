import AppKit
import SwiftUI

/// Basic artwork colors: average of each half. The private package replaces this with a
/// tuned palette extractor of the same API.
public enum ArtworkPalette {
    public static let fallback: [Color] = [Color(white: 0.8, opacity: 0.8), Color(white: 0.45)]


    public static func gradient(from image: NSImage?) -> [Color] {
        guard let image else { return fallback }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width >= 2 else { return [dominantColor(from: image), Color(white: 0.45)] }
        return [0, 1].map { side in
            let area = CGRect(x: side * cg.width / 2, y: 0, width: cg.width / 2, height: cg.height)
            guard let crop = cg.cropping(to: area) else { return dominantColor(from: image) }
            return dominantColor(from: NSImage(cgImage: crop, size: .zero))
        }
    }

    /// Samples the average image color with the AreaAverage filter.
    static func dominantColor(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return Color(white: 0.6)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ])

        guard let output = filter?.outputImage else { return Color(white: 0.6) }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0

        // Increase saturation slightly for visibility on a black background.
        return Color(
            nsColor: NSColor(
                red: min(r * 1.2, 1.0),
                green: min(g * 1.2, 1.0),
                blue: min(b * 1.2, 1.0),
                alpha: 1.0
            )
        )
    }
}
