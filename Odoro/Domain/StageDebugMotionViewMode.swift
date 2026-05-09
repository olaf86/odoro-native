//
//  StageDebugMotionViewMode.swift
//  Odoro
//

import Foundation

enum StageDebugMotionViewMode: String, CaseIterable, Identifiable, Sendable {
    case raw
    case canonical
    case torso
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
        case .stabilized:
            "Stabilized"
        }
    }
}
