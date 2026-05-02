//
//  StudioViewModel+Stage.swift
//  Odoro
//

import Foundation
import RealityKit

extension StudioViewModel {
    func setStageDebugMotionViewMode(_ mode: StageDebugMotionViewMode) {
        guard stageDebugMotionViewMode != mode else { return }
        stageDebugMotionViewMode = mode
        applyStageDebugPresentation()
    }

    func returnToCapture() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.returnToCapture()
        navigate(to: .capture, transition: .fromTrailing)
    }

    func resetClip() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        stageRenderer.setClip(nil)
        stageRenderer.setAvatarRigClip(nil)
        stageRenderer.setAppendagePoses(nil)
        interactor.resetClip()
        currentTakeID = nil
        playbackCaptureMode = nil
        preparedStagePlayback = nil
        storedPlaybackArtifacts = nil
    }

    func prepareStagePlayback() {
        stopAudioPlayback()
        interactor.deactivateSource()
        if stageDebugMotionViewMode != .stabilized {
            stageDebugMotionViewMode = .stabilized
        }
        stageRenderer.setAvatarOption(selectedAvatarOption)
        applyStageDebugPresentation()
        stageRenderer.play()
        interactor.setPlaybackActive(true)
    }

    func pausePlayback() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
    }

    func togglePlayback() {
        if state.isPlaying {
            pausePlayback()
        } else {
            prepareStagePlayback()
        }
    }

    func attachStageView(_ view: ARView) {
        stageRenderer.attach(to: view)
        stageRenderer.setAvatarOption(selectedAvatarOption)
        applyStageDebugPresentation()
    }

    func selectAvatarOption(_ option: StageAvatarOption) {
        guard !isImportingAvatar else { return }

        if option.installState == .notInstalled {
            Task { @MainActor [weak self] in
                await self?.downloadAvatar(option)
            }
            return
        }

        applySelectedAvatarOption(option)
    }

    private func applySelectedAvatarOption(_ option: StageAvatarOption) {
        guard selectedAvatarOption.selection != option.selection || selectedAvatarOption != option else { return }
        selectedAvatarOption = option
        stageRenderer.setAvatarOption(option)

        if option.source == .localDevelopment, option.runtimeFormat == .glb {
            showFeatureNotice("Local GLB import stays available for rig inspection, but stage playback now expects installed USDZ assets.")
        }

        if state.isPlaying {
            prepareStagePlayback()
        } else {
            applyStageDebugPresentation()
        }
    }

    private func downloadAvatar(_ option: StageAvatarOption) async {
        guard !state.isRecording, !isImportingAvatar else {
            return
        }

        guard let variant = AvatarCatalog.variant(for: option.selection) else {
            showFeatureNotice("Avatar download is not configured for this selection.")
            return
        }

        isImportingAvatar = true
        showFeatureNotice("Downloading \(option.titleText)...")

        defer {
            isImportingAvatar = false
        }

        do {
            let installedOption = try await avatarAssetStore.installDownloadableAvatar(from: variant)
            refreshAvatarLibrary()

            if let resolvedOption = availableAvatarOptions.first(where: { $0.selection == installedOption.selection }) {
                applySelectedAvatarOption(resolvedOption)
            }

            showFeatureNotice("Downloaded \(option.titleText). The avatar is installed and ready for stage playback.")
        } catch {
            showFeatureNotice("Avatar download failed: \(error.localizedDescription)")
        }
    }

    var availableStageDebugMotionViewModes: [StageDebugMotionViewMode] {
        interactor.sourceClip == nil ? [.stabilized] : StageDebugMotionViewMode.allCases
    }

    func importAvatar(from url: URL) {
        guard !state.isRecording, !isImportingAvatar else {
            return
        }

        isImportingAvatar = true
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isImportingAvatar = false
        }

        do {
            let option = try avatarAssetStore.installDevelopmentAvatar(from: url)
            refreshAvatarLibrary()
            if let installedOption = availableAvatarOptions.first(where: { $0.selection == option.selection }) {
                selectAvatarOption(installedOption)
            }
            showFeatureNotice("Imported \(option.titleText). Generated package_manifest.json and rig_profile.json were written to Application Support/AvatarAssets.")
        } catch {
            showFeatureNotice("Avatar import failed: \(error.localizedDescription)")
        }
    }

    func refreshAvatarLibrary() {
        let installedOptions = avatarAssetStore.fetchInstalledAvatarOptions()
        availableAvatarOptions = AvatarCatalog.stageOptions(installedOptions: installedOptions)

        if let matchingSelection = availableAvatarOptions.first(where: { $0.selection == selectedAvatarOption.selection }) {
            selectedAvatarOption = matchingSelection
        } else {
            selectedAvatarOption = AvatarCatalog.defaultOption
        }
    }

    func applyStageDebugPresentation() {
        let resolvedMode = availableStageDebugMotionViewModes.contains(stageDebugMotionViewMode)
            ? stageDebugMotionViewMode
            : .stabilized
        if stageDebugMotionViewMode != resolvedMode {
            stageDebugMotionViewMode = resolvedMode
        }

        if preparedStagePlayback == nil {
            rebuildPreparedStagePlayback()
        }

        stageRenderer.setSkeletonDebugLayout(stageDebugSkeletonLayout)
        stageRenderer.setAvatarRigClip(preparedStagePlayback?.avatarRigVariant?.clip)
        stageRenderer.setClip(stageDebugPresentation.clip)
        stageRenderer.setAppendagePoses(stageDebugPresentation.appendagePoses)
        stageRenderer.setStageCameraPreset(stageDebugPresentation.cameraPreset)
    }

    var stageDebugSkeletonLayout: StagePlaybackRenderer.SkeletonDebugLayout {
        switch stageDebugMotionViewMode {
        case .raw:
            .rawARKit
        case .canonical, .stabilized:
            .canonical
        }
    }

    var stageDebugPresentation: PreparedStagePlaybackClip {
        switch stageDebugMotionViewMode {
        case .raw:
            return preparedStagePlayback?.raw
                ?? .empty(
                    purpose: .display,
                    processingStage: .raw,
                    skeletonDefinition: .source,
                    integrity: .displaySafe
                )
        case .canonical:
            return preparedStagePlayback?.canonical
                ?? .empty(
                    purpose: .display,
                    processingStage: .canonical,
                    skeletonDefinition: .odoroCanonical,
                    integrity: .displaySafe
                )
        case .stabilized:
            return preparedStagePlayback?.stabilized
                ?? .empty(
                    purpose: .display,
                    processingStage: .stabilized,
                    skeletonDefinition: .odoroCanonical,
                    integrity: .displaySafe
                )
        }
    }

    var activePlaybackCaptureMode: CaptureMode {
        playbackCaptureMode ?? currentTake?.captureMode ?? captureMode
    }
}
