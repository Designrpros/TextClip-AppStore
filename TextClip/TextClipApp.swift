//
//  TextClip.swift
//  TextClip
//
//  Created by Vegar Berentsen on 23/05/2025.
//

import SwiftUI
import OSLog
import AppKit
import ServiceManagement

@main
struct TextClipApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private let textRecognizer = ScreenTextRecognizer.shared
    
    init() {
        // Start pre-fetching shareable content and permissions at app launch
        let preFetchTask = Task {
            os_log(.info, log: OSLog(subsystem: "Alcatelz.TextClip", category: "ScreenCapture"), "Pre-fetching shareable content and permissions at app launch")
            await ScreenTextRecognizer.shared.fetchShareableContent()
            // Cache permission check
            let isAuthorized = CGPreflightScreenCaptureAccess()
            ScreenTextRecognizer.shared.setInitialPermission(isAuthorized)
            os_log(.info, log: OSLog(subsystem: "Alcatelz.TextClip", category: "ScreenCapture"), "Pre-fetching and initialization completed")
        }
        ScreenTextRecognizer.shared.setPreFetchTask(preFetchTask)
    }
    
    var body: some Scene {
        WindowGroup {
            // The logic to show the window on first launch is here.
            // The AppDelegate will handle re-opening it if the user closes it.
            if !UserDefaults.standard.bool(forKey: "dontShowAgain") {
                ContentView()
            }
        }
        .windowResizability(.contentSize)
        // REMOVED: The conflicting window styles have been removed.
        // The system will now provide a default title bar, allowing the toolbar to appear.
    }
}
