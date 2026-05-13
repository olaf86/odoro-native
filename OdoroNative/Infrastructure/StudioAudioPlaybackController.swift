//
//  StudioAudioPlaybackController.swift
//  Odoro
//

import AVFoundation
import Foundation

protocol StudioAudioPlaybackControlling: AnyObject {
    func playMetronome(with context: MotionRecordingContext)
    func stop()
}

final class StudioAudioPlaybackController: StudioAudioPlaybackControlling {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var currentFormat: AVAudioFormat?
    private var currentBuffer: AVAudioPCMBuffer?

    init() {
        engine.attach(playerNode)
    }

    func playMetronome(with context: MotionRecordingContext) {
        stopPlaybackNode()
        configureAudioSession()

        let format = makePlaybackFormat()
        connectPlayerIfNeeded(using: format)

        let buffer = Self.makeLoopingMetronomeBuffer(for: context, format: format)
        currentBuffer = buffer

        playerNode.scheduleBuffer(buffer, at: nil, options: [.loops])

        do {
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
        } catch {
            print("Failed to start metronome audio engine: \(error)")
        }
    }

    func stop() {
        stopPlaybackNode()
        engine.stop()
        currentBuffer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    private func stopPlaybackNode() {
        if playerNode.isPlaying {
            playerNode.stop()
        }

        playerNode.reset()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func makePlaybackFormat() -> AVAudioFormat {
        let session = AVAudioSession.sharedInstance()
        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100

        return AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) ?? engine.mainMixerNode.outputFormat(forBus: 0)
    }

    private func connectPlayerIfNeeded(using format: AVAudioFormat) {
        let needsReconnect =
            currentFormat?.sampleRate != format.sampleRate ||
            currentFormat?.channelCount != format.channelCount

        guard currentFormat == nil || needsReconnect else {
            return
        }

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        currentFormat = format
    }

    private static func makeLoopingMetronomeBuffer(
        for context: MotionRecordingContext,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let bpm = max(context.bpm, 1)
        let beatsPerBar = max(context.timeSignatureNumerator, 1)
        let beatDuration = 60.0 / bpm
        let barDuration = max(beatDuration * Double(beatsPerBar), 0.25)
        let totalFrameCount = max(Int((barDuration * format.sampleRate).rounded(.up)), 1)
        let clickDuration = min(0.08, beatDuration * 0.45)
        let clickFrameCount = max(Int((clickDuration * format.sampleRate).rounded(.up)), 1)

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrameCount)
            )
        else {
            preconditionFailure("Failed to allocate metronome audio buffer.")
        }

        buffer.frameLength = AVAudioFrameCount(totalFrameCount)

        guard let channelData = buffer.floatChannelData else {
            return buffer
        }

        let channels = Int(format.channelCount)
        let attackFrameCount = max(Int((0.003 * format.sampleRate).rounded(.up)), 1)

        for beatIndex in 0..<beatsPerBar {
            let startFrame = Int((Double(beatIndex) * beatDuration * format.sampleRate).rounded())
            guard startFrame < totalFrameCount else { continue }

            let frequency = beatIndex == 0 ? 1_760.0 : 1_320.0
            let amplitude: Float = beatIndex == 0 ? 0.95 : 0.65

            for frameOffset in 0..<clickFrameCount {
                let frameIndex = startFrame + frameOffset
                guard frameIndex < totalFrameCount else { break }

                let progress = Double(frameOffset) / Double(max(clickFrameCount - 1, 1))
                let attack = min(1.0, Double(frameOffset) / Double(attackFrameCount))
                let decay = pow(max(0.0, 1.0 - progress), 3.5)
                let sample = Float(
                    sin(2 * Double.pi * frequency * Double(frameOffset) / format.sampleRate) *
                    attack *
                    decay
                ) * amplitude

                for channel in 0..<channels {
                    channelData[channel][frameIndex] += sample
                }
            }
        }

        return buffer
    }
}
