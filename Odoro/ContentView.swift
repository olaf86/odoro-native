//
//  ContentView.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import SwiftUI

struct ContentView: View {
    private let archiveStore: MotionArchiveStore?
    private let recordingContext: MotionRecordingContext?

    init(
        archiveStore: MotionArchiveStore? = nil,
        recordingContext: MotionRecordingContext? = nil
    ) {
        self.archiveStore = archiveStore
        self.recordingContext = recordingContext
    }

    var body: some View {
        StudioRootView(
            archiveStore: archiveStore,
            recordingContext: recordingContext
        )
    }
}

#Preview {
    ContentView()
}
