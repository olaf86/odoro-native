//
//  StageDebugMotionViewMode.swift
//  Odoro
//

import Foundation

enum StageDebugMotionViewMode: String, CaseIterable, Identifiable, Sendable {
    case raw
    case canonical
    case torso
    case tPose
    case stabilized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw:
            "Raw"
        case .canonical:
            "Canonical"
        case .torso:
            "Torso"
        case .tPose:
            "T-Pose"
        case .stabilized:
            "Stabilized"
        }
    }
}
