//
//  MotionSource.swift
//  Visco
//

import Foundation

protocol MotionSource: AnyObject {
    var isSupported: Bool { get }
    var onFrame: ((MotionFrame) -> Void)? { get set }
    var onStatusTextChange: ((String) -> Void)? { get set }

    func start()
    func stop()
}
