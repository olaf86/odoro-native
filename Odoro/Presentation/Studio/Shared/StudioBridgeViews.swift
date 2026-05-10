//
//  StudioBridgeViews.swift
//  Odoro
//

import ARKit
import RealityKit
import SwiftUI
import UIKit

struct MockCapturePreviewView: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct MotionCaptureARView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        studio.attachCaptureView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct FrontCameraCaptureView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        studio.attachFrontCaptureView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        studio.updateFrontCapturePreview(in: uiView)
    }
}

struct StagePlaybackView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var studio: StudioViewModel

        init(studio: StudioViewModel) {
            self.studio = studio
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else {
                return
            }

            let translation = recognizer.translation(in: recognizer.view)
            studio.orbitStageDebugCamera(horizontalPoints: translation.x, verticalPoints: translation.y)
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else {
                return
            }

            studio.zoomStageDebugCamera(scaleDelta: recognizer.scale)
            recognizer.scale = 1
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            studio.resetStageDebugCamera()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(studio: studio)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        studio.attachStageView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.studio = studio
    }
}
