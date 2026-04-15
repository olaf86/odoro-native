//
//  OdoroApp.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import SwiftUI
import SwiftData

@main
struct OdoroApp: App {
    private let sharedModelContainer: ModelContainer
    private let archiveStore: MotionArchiveStore

    init() {
        let schema = Schema([
            RecordingSessionRecord.self,
            MotionTakeRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            self.archiveStore = MotionArchiveStore(modelContainer: container)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(archiveStore: archiveStore)
        }
        .modelContainer(sharedModelContainer)
    }
}
