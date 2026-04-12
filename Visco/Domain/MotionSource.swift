//
//  MotionSource.swift
//  Visco
//

import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case rearBody3D
    case frontUpperBody
    case mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rearBody3D:
            "Rear 3D"
        case .frontUpperBody:
            "Front Upper"
        case .mock:
            "Mock"
        }
    }

    var descriptionText: String {
        switch self {
        case .rearBody3D:
            "背面カメラで全身の 3D body tracking を使います。"
        case .frontUpperBody:
            "前面カメラで上半身の pose を検出して収録します。"
        case .mock:
            "疑似ダンスを入力源にして収録フローを確認します。"
        }
    }
}

protocol MotionSource: AnyObject {
    var captureMode: CaptureMode { get }
    var isSupported: Bool { get }
    var onFrame: ((MotionFrame) -> Void)? { get set }
    var onStatusTextChange: ((String) -> Void)? { get set }

    func start()
    func stop()
}
