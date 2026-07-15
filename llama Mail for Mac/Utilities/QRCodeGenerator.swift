//
//  QRCodeGenerator.swift
//  llama Mail
//
//  QR rendering for "My QR Code" (Client_PGP_Update.md). CoreImage ships on
//  both platforms, so this needs no third-party dependency — unlike scanning,
//  which is VisionKit/iOS-only (see QRScannerView).
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

enum QRCodeGenerator {
    /// Renders `string` as a QR code.
    ///
    /// Returns a CGImage rather than NSImage/UIImage so callers stay
    /// cross-platform: SwiftUI's `Image(decorative:scale:)` takes one directly.
    ///
    /// CoreImage emits one pixel per module, which scales up blurry by default;
    /// callers pair this with `.interpolation(.none)` to keep the edges crisp.
    /// Correction level M per the guide — enough redundancy to survive a phone
    /// screen's glare without inflating the module count.
    static func cgImage(for string: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
