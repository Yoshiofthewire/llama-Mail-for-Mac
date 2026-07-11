//
//  QRScannerView.swift
//  llama Mail
//
//  Live camera QR scanner (VisionKit data scanner), the default pairing entry
//  point on iOS. macOS pairs via deep links, so this view is iOS-only.
//

#if os(iOS)
import SwiftUI
import Vision
import VisionKit
import AVFoundation

/// Camera view that reports the payload of the first QR code it recognizes.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called once with the payload of the first recognized QR code.
    let onCode: (String) -> Void

    /// Device supports live scanning (requires A12 chip or later).
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Prompts for camera access if needed; returns whether scanning may start.
    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // startScanning throws only when the camera is unavailable; the
        // pairing screen falls back to paste-a-link in that case.
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}
#endif
