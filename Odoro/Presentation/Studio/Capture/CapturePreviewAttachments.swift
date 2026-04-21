//
//  CapturePreviewAttachments.swift
//  Odoro
//

import RealityKit
import UIKit

struct CapturePreviewAttachments {
    weak var captureARView: ARView?
    weak var frontPreviewView: UIView?

    mutating func attachCaptureView(_ view: ARView, to source: MotionSource) {
        captureARView = view
        (source as? ARKitMotionSource)?.attach(to: view)
    }

    mutating func attachFrontPreviewView(_ view: UIView, to source: MotionSource) {
        frontPreviewView = view
        (source as? VisionFrontCameraMotionSource)?.attachPreview(to: view)
    }

    func updateFrontPreviewFrame(in view: UIView, source: MotionSource) {
        (source as? VisionFrontCameraMotionSource)?.updatePreviewFrame(to: view.bounds)
    }

    func attachCurrentSourceIfPossible(_ source: MotionSource) {
        if let captureARView {
            (source as? ARKitMotionSource)?.attach(to: captureARView)
        }

        if let frontPreviewView {
            (source as? VisionFrontCameraMotionSource)?.attachPreview(to: frontPreviewView)
        }
    }
}
