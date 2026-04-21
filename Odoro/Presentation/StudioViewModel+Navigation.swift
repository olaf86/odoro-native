//
//  StudioViewModel+Navigation.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    func goBack() {
        switch screen {
        case .capture:
            break
        case .musicSelection:
            navigate(to: .capture, transition: .fromTrailing)
        case .sessionSettings:
            navigate(to: .capture, transition: .fromBottom)
        case .clipsLibrary:
            navigate(to: .capture, transition: .fromLeading)
        case .stage:
            returnToCapture()
        case .modelSelection:
            navigate(to: .stage, transition: .fromBottom)
        case .archive:
            navigate(to: .stage, transition: .fromTrailing)
        }
    }

    func openMusicSelection() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .musicSelection, transition: .fromLeading)
    }

    func openSessionSettings() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .sessionSettings, transition: .fromTop)
    }

    func openClipLibrary() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        refreshLibrary()
        navigate(to: .clipsLibrary, transition: .fromTrailing)
    }

    func openModelSelection() {
        guard hasClip else { return }
        navigate(to: .modelSelection, transition: .fromTop)
    }

    func revealSwipeHints() {
        guard !state.isRecording, screen == .capture else { return }

        swipeHintDismissTask?.cancel()
        swipeHintsVisible = true
        swipeHintDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissSwipeHints()
        }
    }

    func dismissSwipeHints() {
        swipeHintDismissTask?.cancel()
        swipeHintsVisible = false
    }

    func showFeatureNotice(_ message: String) {
        transientMessageDismissTask?.cancel()
        transientMessage = message
        transientMessageDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.clearFeatureNotice()
        }
    }

    func clearFeatureNotice() {
        transientMessageDismissTask?.cancel()
        transientMessage = nil
    }

    func navigate(to screen: StudioScreen, transition: StudioScreenTransition) {
        guard self.screen != screen || screenTransition != transition else {
            return
        }

        if self.screen == .musicSelection, screen != .musicSelection {
            stopAudioPreview()
        }

        self.screen = screen
        self.screenTransition = transition
    }
}
