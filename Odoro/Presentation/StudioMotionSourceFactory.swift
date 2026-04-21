//
//  StudioMotionSourceFactory.swift
//  Odoro
//

import Foundation

#if canImport(ARKit)
import ARKit
#endif

enum StudioMotionSourceFactory {
    static func makeSupportedCaptureModes() -> [CaptureMode] {
        #if targetEnvironment(simulator)
        return [.mock]
        #elseif os(iOS)
        var modes: [CaptureMode] = []

        #if canImport(ARKit)
        if ARBodyTrackingConfiguration.isSupported {
            modes.append(.rearBody3D)
        }
        #endif

        if VisionFrontCameraMotionSource().isSupported {
            modes.append(.frontUpperBody)
        }

        modes.append(.mock)
        return modes
        #else
        return [.mock]
        #endif
    }

    static func makeMotionSource(for mode: CaptureMode) -> MotionSource {
        switch mode {
        case .rearBody3D:
            #if canImport(ARKit)
            ARKitMotionSource()
            #else
            MockMotionSource()
            #endif
        case .frontUpperBody:
            #if os(iOS)
            VisionFrontCameraMotionSource()
            #else
            MockMotionSource()
            #endif
        case .importedVideo:
            MockMotionSource()
        case .mock:
            MockMotionSource()
        }
    }
}
