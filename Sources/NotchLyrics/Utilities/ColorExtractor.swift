import AppKit
import SwiftUI

/// ดึงสีหลักจาก album art เพื่อใช้เป็น accent color
enum ColorExtractor {

    static func gradient(from image: NSImage?) -> [Color] {
        guard let image else { return [.purple, .pink] }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width >= 2 else { return [dominantColor(from: image), .purple] }
        return [0, 1].map { side in
            let area = CGRect(x: side * cg.width / 2, y: 0, width: cg.width / 2, height: cg.height)
            guard let crop = cg.cropping(to: area) else { return dominantColor(from: image) }
            return dominantColor(from: NSImage(cgImage: crop, size: .zero))
        }
    }

    /// ดึงสีเด่นจากรูป (ใช้ CIFilter AreaAverage)
    static func dominantColor(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return .purple
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ])

        guard let output = filter?.outputImage else { return .purple }

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

        // เพิ่ม saturation เล็กน้อยเพื่อให้สีชัดขึ้นบนพื้นดำ
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
