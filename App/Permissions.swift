import Foundation
import AVFoundation
import LucentCore

@MainActor
public final class Permissions: ObservableObject {
    @Published public var cameraGranted = false
    @Published public var accessibilityGranted = false

    public var allGranted: Bool { cameraGranted && accessibilityGranted }

    public init() { refresh() }

    public func refresh() {
        cameraGranted = CameraManager.authorizationStatus == .authorized
        accessibilityGranted = InputController.hasAccessibilityPermission
    }

    public func requestCamera() async {
        cameraGranted = await CameraManager.requestPermission()
    }

    public func requestAccessibility() {
        InputController.requestAccessibilityPermission()
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if InputController.hasAccessibilityPermission {
                    accessibilityGranted = true
                    return
                }
            }
        }
    }
}
