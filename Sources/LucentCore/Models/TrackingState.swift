import Foundation

public enum TrackingState: Equatable, Sendable {
    case idle
    case detecting
    case tracking
    case calibrating
    case paused(reason: PauseReason)

    public enum PauseReason: Equatable, Sendable {
        case faceLost
        case poorLighting
        case cameraDisconnected
        case userPaused
    }
}
