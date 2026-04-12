import Foundation
import AVFoundation

public protocol CameraManagerDelegate: AnyObject, Sendable {
    func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

public final class CameraManager: NSObject, @unchecked Sendable {
    public weak var delegate: CameraManagerDelegate?
    public let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "com.lucent.camera", qos: .userInteractive)
    private var videoOutput: AVCaptureVideoDataOutput?
    public private(set) var isRunning = false
    public private(set) var currentDeviceID: String?

    public override init() { super.init() }

    public static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static var availableCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified
        ).devices
    }

    public func start(preferredDeviceID: String? = nil) throws {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        let device: AVCaptureDevice?
        if let id = preferredDeviceID { device = AVCaptureDevice(uniqueID: id) }
        else { device = AVCaptureDevice.default(for: .video) }
        guard let camera = device else { throw CameraError.noCameraAvailable }
        currentDeviceID = camera.uniqueID
        try camera.lockForConfiguration()
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        camera.unlockForConfiguration()
        let input = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        videoOutput = output
        session.commitConfiguration()
        session.startRunning()
        isRunning = true
    }

    public func stop() { session.stopRunning(); isRunning = false }

    public enum CameraError: Error, LocalizedError {
        case noCameraAvailable, permissionDenied
        public var errorDescription: String? {
            switch self {
            case .noCameraAvailable: return "No camera found"
            case .permissionDenied: return "Camera permission denied"
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.cameraManager(self, didOutput: pixelBuffer, timestamp: timestamp)
    }
}
