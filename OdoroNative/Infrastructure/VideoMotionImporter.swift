//
//  VideoMotionImporter.swift
//  Odoro
//

import AVFoundation
import Foundation
import ImageIO
import Vision

enum VideoMotionImportError: LocalizedError {
    case missingVideoTrack
    case cannotReadVideo

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "The selected file doesn't contain a video track."
        case .cannotReadVideo:
            "Couldn't read frames from the selected video."
        }
    }
}

struct VideoMotionImporter: Sendable {
    private let targetFrameInterval: TimeInterval

    init(targetFrameInterval: TimeInterval = 1.0 / 30.0) {
        self.targetFrameInterval = targetFrameInterval
    }

    func importClip(from url: URL, maximumDuration: TimeInterval) async throws -> MotionClip {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let clip = try makeClip(from: url, maximumDuration: maximumDuration)
                    continuation.resume(returning: clip)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeClip(from url: URL, maximumDuration: TimeInterval) throws -> MotionClip {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoMotionImportError.missingVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw VideoMotionImportError.cannotReadVideo
        }

        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? VideoMotionImportError.cannotReadVideo
        }

        let orientation = cgImageOrientation(for: videoTrack.preferredTransform)
        var frames: [MotionFrame] = []
        var firstTimestamp: TimeInterval?
        var lastAcceptedTime: TimeInterval = -.greatestFiniteMagnitude

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if firstTimestamp == nil {
                firstTimestamp = timestamp
            }

            let relativeTime = timestamp - (firstTimestamp ?? timestamp)
            if relativeTime > maximumDuration {
                break
            }

            if !frames.isEmpty && relativeTime - lastAcceptedTime < targetFrameInterval {
                continue
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            try handler.perform([request])

            guard
                let observation = request.results?.first,
                let frame = VisionBodyPoseFrameBuilder.makeFrame(from: observation, at: relativeTime)
            else {
                continue
            }

            frames.append(frame)
            lastAcceptedTime = relativeTime
        }

        if reader.status == .failed {
            throw reader.error ?? VideoMotionImportError.cannotReadVideo
        }

        return MotionClip(frames: frames)
    }

    private func cgImageOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (1, 0, 0, 1):
            .up
        case (-1, 0, 0, -1):
            .down
        case (0, 1, -1, 0):
            .right
        case (0, -1, 1, 0):
            .left
        default:
            .up
        }
    }
}
