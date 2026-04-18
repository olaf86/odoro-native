//
//  MotionSource.swift
//  Odoro
//

import Foundation

enum CaptureMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case rearBody3D
    case frontUpperBody
    case importedVideo
    case mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rearBody3D:
            L10n.captureModeRearTitle
        case .frontUpperBody:
            L10n.captureModeFrontTitle
        case .importedVideo:
            L10n.captureModeImportedTitle
        case .mock:
            L10n.captureModeMockTitle
        }
    }

    var descriptionText: String {
        switch self {
        case .rearBody3D:
            L10n.captureModeRearDescription
        case .frontUpperBody:
            L10n.captureModeFrontDescription
        case .importedVideo:
            L10n.captureModeImportedDescription
        case .mock:
            L10n.captureModeMockDescription
        }
    }
}

protocol MotionSource: AnyObject {
    var captureMode: CaptureMode { get }
    var isSupported: Bool { get }
    var onFrame: ((MotionFrame) -> Void)? { get set }
    var onStatusTextChange: ((String) -> Void)? { get set }

    func activate()
    func deactivate()
}
