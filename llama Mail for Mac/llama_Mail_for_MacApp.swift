//
//  llama_Mail_for_MacApp.swift
//  llama Mail for Mac
//
//  Created by Matthew Beacher on 7/10/26.
//

import SwiftUI
import SwiftData

@main
struct llama_Mail_for_MacApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
