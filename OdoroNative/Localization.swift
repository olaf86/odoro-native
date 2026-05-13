//
//  Localization.swift
//  Odoro
//

import Foundation

enum L10n {
    private static let englishBundle: Bundle? = {
        guard
            let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return nil
        }

        return bundle
    }()

    static func text(_ key: String) -> String {
        let localized = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if localized != key {
            return localized
        }

        if let englishBundle {
            let english = englishBundle.localizedString(forKey: key, value: key, table: nil)
            if english != key {
                return english
            }
        }

        return key
    }

    static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static let captureTitle = text("capture.title")
    static let captureModeLabel = text("capture.mode.label")
    static let captureHintMock = text("capture.hint.mock")
    static let captureHintFront = text("capture.hint.front")
    static let captureHintRear = text("capture.hint.rear")
    static let buttonConfirmTake = text("button.confirmTake")
    static let sessionTitle = "Recording Session"
    static let sessionBPMTitle = "BPM"
    static let sessionTimeSignatureTitle = "Meter"
    static let sessionBarsTitle = "Bars"
    static let sessionCountInTitle = "Count-In"
    static let savedTakesTitle = "Saved Takes"
    static let buttonImportVideo = "Import Video"
    static let buttonOpenTake = "Open"
    static let emptySavedTakes = "Your takes for this session will appear here."
    static let stageTitle = text("stage.title")
    static let stageDescription = text("stage.description")
    static let stageReviewTitle = text("stage.review.title")
    static let stageReviewEmpty = text("stage.review.empty")
    static let stageCurrentTakeLabel = text("stage.currentTake.label")
    static let stageAcceptedTakeLabel = text("stage.acceptedTake.label")
    static let buttonRecording = text("button.recording")
    static let buttonStartCapture = text("button.startCapture")
    static let buttonStop = text("button.stop")
    static let buttonReplayStage = text("button.replayStage")
    static let buttonTakeConfirmed = text("button.takeConfirmed")
    static let buttonPause = text("button.pause")
    static let buttonPlay = text("button.play")
    static let buttonRecordAgain = text("button.recordAgain")
    static let buttonResetClip = text("button.resetClip")

    static let captureModeRearTitle = text("captureMode.rear.title")
    static let captureModeFrontTitle = text("captureMode.front.title")
    static let captureModeImportedTitle = "Imported Video"
    static let captureModeMockTitle = text("captureMode.mock.title")
    static let captureModeRearDescription = text("captureMode.rear.description")
    static let captureModeFrontDescription = text("captureMode.front.description")
    static let captureModeImportedDescription = "Analyze an uploaded video with Vision pose detection."
    static let captureModeMockDescription = text("captureMode.mock.description")

    static let statusStandInFrame = text("status.standInFrame")
    static let statusRecordingMoveFullBody = text("status.recording.moveFullBody")
    static let statusInsufficientMotion = text("status.insufficientMotion")
    static let statusCaptureComplete = text("status.captureComplete")
    static let statusClipExists = text("status.clipExists")
    static let statusClipReset = text("status.clipReset")
    static let statusRecordingSaving = text("status.recording.saving")
    static let statusBodyDetected = text("status.bodyDetected")
    static let statusMockGenerating = text("status.mockGenerating")

    static let statusARUnsupported = text("status.ar.unsupported")
    static let statusARPreparingPreview = text("status.ar.preparingPreview")
    static func statusARSessionFailed(_ error: String) -> String {
        formatted("status.ar.sessionFailed", error)
    }
    static let statusARInterrupted = text("status.ar.interrupted")
    static let statusARResumed = text("status.ar.resumed")

    static let statusFrontCameraUnsupported = text("status.front.unsupported")
    static let statusFrontPreparingPreview = text("status.front.preparingPreview")
    static let statusFrontPermissionDenied = text("status.front.permissionDenied")
    static func statusFrontSetupFailed(_ error: String) -> String {
        formatted("status.front.setupFailed", error)
    }
    static let statusFrontDetecting = text("status.front.detecting")
    static func statusFrontPoseFailed(_ error: String) -> String {
        formatted("status.front.poseFailed", error)
    }
    static let statusFrontMoveIntoFrame = text("status.front.moveIntoFrame")
    static let statusFrontReady = text("status.front.ready")
    static let statusVideoImportAnalyzing = "Analyzing video..."
    static let statusVideoImportComplete = "Video analysis complete."
    static let statusVideoImportNoMotion = "Couldn't detect enough body motion in that video."
    static func statusVideoImportFailed(_ error: String) -> String {
        "Video import failed: \(error)"
    }

    static func frames(_ count: Int) -> String {
        formatted("label.frames", count)
    }

    static func recordingDuration(_ value: String) -> String {
        formatted("label.recordingDuration", value)
    }

    static func clipDuration(_ value: String) -> String {
        formatted("label.clipDuration", value)
    }

    static func recordingSessionSummary(_ bpm: Int, _ numerator: Int, _ denominator: Int, _ bars: Int) -> String {
        "\(bpm) BPM • \(numerator)/\(denominator) • \(bars) bars"
    }

    static func takeCardTitle(_ index: Int) -> String {
        "Take \(index)"
    }

    static func takeCardMeta(_ duration: String, _ frameCount: Int) -> String {
        "\(duration)s • \(frameCount) frames"
    }

    static let takeBadgeAccepted = text("take.badge.accepted")
    static let takeBadgeCurrent = text("take.badge.current")
}
