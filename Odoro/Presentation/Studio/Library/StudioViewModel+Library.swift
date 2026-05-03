//
//  StudioViewModel+Library.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    func saveCurrentClipToArchive() {
        guard state.hasClip else { return }
        confirmCurrentTake()
        refreshLibrary()
        navigate(to: .archive, transition: .fromLeading)
    }

    func loadTake(_ take: MotionTakeSummary) {
        guard let archiveStore else { return }

        do {
            if let sessionSummary = try archiveStore.fetchSessionSummary(withID: take.sessionID) {
                recordingContext = Self.normalizedRecordingContext(sessionSummary.recordingContext)
                interactor.updateMaximumCaptureDuration(recordingContext.fixedCaptureDuration)
            }

            let storedTake = try archiveStore.loadStoredTake(
                withID: take.id,
                fromLocalFilePath: take.localFilePath
            )
            currentSessionID = take.sessionID
            currentTakeID = take.id
            playbackCaptureMode = take.captureMode
            storedHints = storedTake.hints
            storedRigClip = storedTake.rigClip
            stageRenderer.setUsesProceduralMockPlayback(take.captureMode == .mock)
            interactor.replaceCurrentClip(storedTake.clip)
            try refreshCurrentSessionTakes()
            interactor.enterStageMode()
        } catch {
            print("Failed to load motion take: \(error)")
        }
    }

    func openTakeFromLibrary(_ take: MotionTakeSummary) {
        loadTake(take)
        navigate(to: .stage, transition: .fromLeading)
    }

    func renameClip(_ take: MotionTakeSummary, to clipName: String) {
        guard let archiveStore else { return }

        do {
            try archiveStore.renameTake(withID: take.id, clipName: clipName)
            try refreshCurrentSessionTakes()
            refreshLibrary()
        } catch {
            print("Failed to rename clip: \(error)")
        }
    }

    func reportVideoImportFailure(_ error: Error) {
        let message = L10n.statusVideoImportFailed(error.localizedDescription)
        interactor.setStatusText(message)
        showFeatureNotice(message)
    }

    func importVideo(from url: URL) async {
        guard
            let archiveStore,
            !state.isRecording,
            !isImportingVideo
        else {
            return
        }

        isImportingVideo = true
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.setStatusText(L10n.statusVideoImportAnalyzing)
        showFeatureNotice(L10n.statusVideoImportAnalyzing)

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isImportingVideo = false
        }

        do {
            let clip = try await videoImporter.importClip(
                from: url,
                maximumDuration: maximumImportedVideoDuration
            )

            guard clip.frameCount > 1 else {
                let message = L10n.statusVideoImportNoMotion
                interactor.setStatusText(message)
                showFeatureNotice(message)
                return
            }

            let normalizedClip = Self
                .makeCapturedClipPreparer(for: .importedVideo)
                .prepareCapturedClip(clip)
            let saveResult = try archiveStore.saveTake(
                clip: normalizedClip,
                clipIsCanonical: true,
                captureMode: .importedVideo,
                recordingContext: recordingContext,
                existingSessionID: currentSessionID
            )

            currentSessionID = saveResult.sessionID
            currentTakeID = saveResult.takeID
            playbackCaptureMode = .importedVideo
            let storedTake = try archiveStore.loadStoredTake(
                withID: saveResult.takeID,
                fromLocalFilePath: saveResult.localFilePath
            )
            storedHints = storedTake.hints
            storedRigClip = storedTake.rigClip
            stageRenderer.setUsesProceduralMockPlayback(false)
            interactor.replaceCurrentClip(storedTake.clip, sourceClip: clip)
            try refreshCurrentSessionTakes()
            refreshLibrary()
            interactor.setStatusText(L10n.statusVideoImportComplete)
            interactor.enterStageMode()
        } catch {
            reportVideoImportFailure(error)
        }
    }

    func confirmCurrentTake() {
        do {
            let takeToConfirm = try ensureCurrentTakeForConfirmation()
            try archiveStore?.acceptTake(withID: takeToConfirm.id, inSessionID: takeToConfirm.sessionID)
            try refreshCurrentSessionTakes()
            refreshLibrary()
        } catch {
            print("Failed to confirm motion take: \(error)")
        }
    }

    func persistCurrentClipIfPossible() {
        guard let currentClip = interactor.currentClip else {
            return
        }

        do {
            try persistClip(currentClip, sourceClip: interactor.sourceClip, captureMode: captureMode)
        } catch {
            print("Failed to persist motion take: \(error)")
        }
    }

    func persistClip(_ clip: MotionClip, sourceClip: MotionClip? = nil, captureMode: CaptureMode) throws {
        guard let archiveStore else {
            return
        }

        let saveResult = try archiveStore.saveTake(
            clip: clip,
            sourceClip: sourceClip,
            clipIsCanonical: true,
            captureMode: captureMode,
            recordingContext: recordingContext,
            existingSessionID: currentSessionID
        )
        currentSessionID = saveResult.sessionID
        currentTakeID = saveResult.takeID
        playbackCaptureMode = captureMode
        let storedTake = try archiveStore.loadStoredTake(
            withID: saveResult.takeID,
            fromLocalFilePath: saveResult.localFilePath
        )
        storedHints = storedTake.hints
        storedRigClip = storedTake.rigClip
        stageRenderer.setUsesProceduralMockPlayback(captureMode == .mock)
        interactor.replaceCurrentClip(
            playbackClip(for: clip, savedClip: storedTake.clip, captureMode: captureMode),
            sourceClip: interactor.sourceClip
        )
        try refreshCurrentSessionTakes()
    }

    private func playbackClip(
        for sourceClip: MotionClip,
        savedClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionClip {
        switch captureMode {
        case .rearBody3D:
            sourceClip
        case .frontUpperBody, .mock, .importedVideo:
            savedClip
        }
    }

    func ensureCurrentTakeForConfirmation() throws -> MotionTakeSummary {
        if let currentTake {
            return currentTake
        }

        guard
            let archiveStore,
            let currentClip = interactor.currentClip
        else {
            throw ConfirmationError.missingClip
        }

        let saveResult = try archiveStore.saveTake(
            clip: currentClip,
            clipIsCanonical: true,
            captureMode: captureMode,
            recordingContext: recordingContext,
            existingSessionID: currentSessionID
        )
        currentSessionID = saveResult.sessionID
        currentTakeID = saveResult.takeID
        let storedTake = try archiveStore.loadStoredTake(
            withID: saveResult.takeID,
            fromLocalFilePath: saveResult.localFilePath
        )
        storedHints = storedTake.hints
        storedRigClip = storedTake.rigClip
        try refreshCurrentSessionTakes()

        guard let persistedTake = currentTake else {
            throw ConfirmationError.missingTakeAfterSave
        }

        return persistedTake
    }

    func refreshCurrentSessionTakes() throws {
        guard let archiveStore, let currentSessionID else {
            currentSessionTakes = []
            return
        }

        currentSessionTakes = try archiveStore.fetchTakeSummaries(inSessionID: currentSessionID)
    }

    func refreshLibrary() {
        guard let archiveStore else {
            libraryClips = []
            return
        }

        do {
            libraryClips = try archiveStore.fetchAllTakeSummaries()
        } catch {
            print("Failed to fetch clip library: \(error)")
            libraryClips = []
        }
    }

    var currentTake: MotionTakeSummary? {
        guard let currentTakeID else {
            return currentSessionTakes.first
        }

        return currentSessionTakes.first { $0.id == currentTakeID } ?? currentSessionTakes.first
    }
}

private enum ConfirmationError: Error {
    case missingClip
    case missingTakeAfterSave
}
