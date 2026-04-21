//
//  StudioViewModel+Stage.swift
//  Odoro
//

import Foundation
import RealityKit

extension StudioViewModel {
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
        interactor.resetClip()
        currentTakeID = nil
    }

    func prepareStagePlayback() {
        stopAudioPlayback()
        interactor.deactivateSource()
        stageRenderer.setAvatarOption(selectedAvatarOption)
        stageRenderer.setClip(interactor.currentClip)
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
        stageRenderer.setClip(interactor.currentClip)
    }

    func selectAvatarOption(_ option: StageAvatarOption) {
        guard selectedAvatarOption.selection != option.selection else { return }
        selectedAvatarOption = option
        stageRenderer.setAvatarOption(option)

        if !option.isReadyForPlayback {
            showFeatureNotice("On-demand avatar downloads are next. Playback falls back to the skeleton preview until the package is installed.")
        } else if option.runtimeFormat == .glb {
            showFeatureNotice("GLB import is installed locally. If RealityKit cannot load this file directly yet, stage playback will fall back to the skeleton preview.")
        }

        if state.isPlaying {
            prepareStagePlayback()
        } else {
            stageRenderer.setClip(interactor.currentClip)
        }
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
        let builtInOptions = AvatarCatalog.builtInStageOptions
        let installedOptions = avatarAssetStore.fetchInstalledAvatarOptions()
        availableAvatarOptions = builtInOptions + installedOptions

        if let matchingSelection = availableAvatarOptions.first(where: { $0.selection == selectedAvatarOption.selection }) {
            selectedAvatarOption = matchingSelection
        } else {
            selectedAvatarOption = AvatarCatalog.defaultOption
        }
    }
}
