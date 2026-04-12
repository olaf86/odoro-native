//
//  Localization.swift
//  Visco
//

import Foundation

enum L10n {
    static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
    }

    static func formatted(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
        let format = text(key, fallback)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static let captureTitle = text("capture.title", "Visco Capture")
    static let captureModeLabel = text("capture.mode.label", "Capture Mode")
    static let captureHintMock = text("capture.hint.mock", "Using MockMotionSource for simulator testing. The mock dance clip is treated as the capture source.")
    static let captureHintFront = text("capture.hint.front", "Capture upper-body motion from the front camera, centered on shoulders, arms, and wrists. Lower body motion is filled in during stage playback.")
    static let captureHintRear = text("capture.hint.rear", "Capture a short performance using the rear camera and full body tracking. The app switches to stage playback when you stop recording.")
    static let stageTitle = text("stage.title", "Visco Stage")
    static let stageDescription = text("stage.description", "Recorded joint positions are looped as a simplified dancer. This is a mock stage player that will later be replaced with a rigged character.")
    static let buttonRecording = text("button.recording", "Recording...")
    static let buttonStartCapture = text("button.startCapture", "Start Capture")
    static let buttonStop = text("button.stop", "Stop")
    static let buttonReplayStage = text("button.replayStage", "Replay Stage")
    static let buttonPause = text("button.pause", "Pause")
    static let buttonPlay = text("button.play", "Play")
    static let buttonRecordAgain = text("button.recordAgain", "Record Again")
    static let buttonResetClip = text("button.resetClip", "Reset Clip")
    static let mockDanceTitle = text("mock.title", "Mock Dance Source")
    static let mockDanceDescription = text("mock.description", "Use a synthetic dance clip instead of the camera to verify the flow from capture to playback.")

    static let captureModeRearTitle = text("captureMode.rear.title", "Rear 3D")
    static let captureModeFrontTitle = text("captureMode.front.title", "Front Upper")
    static let captureModeMockTitle = text("captureMode.mock.title", "Mock")
    static let captureModeRearDescription = text("captureMode.rear.description", "Use full-body 3D tracking with the rear camera.")
    static let captureModeFrontDescription = text("captureMode.front.description", "Detect and record upper-body pose with the front camera.")
    static let captureModeMockDescription = text("captureMode.mock.description", "Use a synthetic dance source to verify the capture flow.")

    static let statusStandInFrame = text("status.standInFrame", "Stand where your full body is visible.")
    static let statusRecordingMoveFullBody = text("status.recording.moveFullBody", "Recording. Move so your full body stays in frame.")
    static let statusInsufficientMotion = text("status.insufficientMotion", "Not enough motion was captured. Please try again.")
    static let statusCaptureComplete = text("status.captureComplete", "Capture complete. You can replay it on the stage.")
    static let statusClipExists = text("status.clipExists", "A captured clip is available. You can overwrite it if needed.")
    static let statusClipReset = text("status.clipReset", "The clip was reset. You can record a new one.")
    static let statusRecordingSaving = text("status.recording.saving", "Recording. Saving motion for stage playback.")
    static let statusBodyDetected = text("status.bodyDetected", "Body detected. You can start recording.")
    static let statusMockGenerating = text("status.mockGenerating", "Generating a synthetic dance with MockMotionSource.")

    static let statusARUnsupported = text("status.ar.unsupported", "AR body tracking is not available on this device.")
    static let statusARPreparingPreview = text("status.ar.preparingPreview", "Preparing the AR preview.")
    static func statusARSessionFailed(_ error: String) -> String {
        formatted("status.ar.sessionFailed", "AR session failed: %@", error)
    }
    static let statusARInterrupted = text("status.ar.interrupted", "The AR session was interrupted.")
    static let statusARResumed = text("status.ar.resumed", "The AR session resumed.")

    static let statusFrontCameraUnsupported = text("status.front.unsupported", "The front camera is not available on this device.")
    static let statusFrontPreparingPreview = text("status.front.preparingPreview", "Preparing the front camera preview.")
    static let statusFrontPermissionDenied = text("status.front.permissionDenied", "Camera access is required to start front camera capture.")
    static func statusFrontSetupFailed(_ error: String) -> String {
        formatted("status.front.setupFailed", "Failed to configure the front camera: %@", error)
    }
    static let statusFrontDetecting = text("status.front.detecting", "Detecting upper-body motion with the front camera.")
    static func statusFrontPoseFailed(_ error: String) -> String {
        formatted("status.front.poseFailed", "Front camera pose detection failed: %@", error)
    }
    static let statusFrontMoveIntoFrame = text("status.front.moveIntoFrame", "Move so your upper body stays visible in frame.")
    static let statusFrontReady = text("status.front.ready", "Upper body detected on the front camera. You can start recording.")

    static func frames(_ count: Int) -> String {
        formatted("label.frames", "%d frames", count)
    }

    static func recordingDuration(_ value: String) -> String {
        formatted("label.recordingDuration", "%@ s", value)
    }

    static func clipDuration(_ value: String) -> String {
        formatted("label.clipDuration", "%@ s clip", value)
    }
}
