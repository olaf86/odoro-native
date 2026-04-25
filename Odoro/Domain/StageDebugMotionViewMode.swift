//
//  StageDebugMotionViewMode.swift
//  Odoro
//

import Foundation

enum StageDebugMotionViewMode: String, CaseIterable, Identifiable, Sendable {
    case raw
    case canonical
    case stabilized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw:
            "Raw"
        case .canonical:
            "Canonical"
        case .stabilized:
            "Stabilized"
        }
    }
}
