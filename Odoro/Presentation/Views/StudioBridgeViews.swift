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

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        studio.attachStageView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
