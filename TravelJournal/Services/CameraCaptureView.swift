import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

/// Wraps UIImagePickerController (.camera). Date = now; location only if permission is already granted
/// (never prompts). On devices without a camera (Simulator) shows a friendly message instead.
struct CameraCaptureView: View {
    var onCapture: (PhotoMeta) -> Void
    var onCancel: () -> Void = {}

    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        if Self.isCameraAvailable {
            CameraPicker(onCapture: onCapture, onCancel: onCancel).ignoresSafeArea()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "camera.slash").font(.largeTitle)
                Text("Camera unavailable").font(.headline)
                Text("This device can't take photos right now. You can still add photos from your library.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Close", action: onCancel).buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (PhotoMeta) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.mediaTypes = [UTType.image.identifier]
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { picker.dismiss(animated: true) }
            // UIImage.jpegData bakes orientation into the pixels.
            guard let image = info[.originalImage] as? UIImage,
                  let raw = image.jpegData(compressionQuality: 0.95) else { parent.onCancel(); return }
            var lat: Double?, lon: Double?
            let mgr = CLLocationManager()
            let status = mgr.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways,
               let c = mgr.location?.coordinate, CLLocationCoordinate2DIsValid(c) {
                lat = c.latitude; lon = c.longitude
            }
            if let meta = PhotoMetaFactory.make(data: raw, assetDate: Date(), assetLatitude: lat, assetLongitude: lon) {
                parent.onCapture(meta)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
            picker.dismiss(animated: true)
        }
    }
}
