//
//  ContentView.swift
//  TextClip
//
//  Created by Vegar Berentsen on 23/05/2025.
//

import SwiftUI
import ServiceManagement
import OSLog

struct ContentView: View {
    // State for checkboxes
    @State private var dontShowAgain: Bool = UserDefaults.standard.bool(forKey: "dontShowAgain")
    
    // State for the new sidebar
    @State private var showInfo: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Main content view
            VStack(spacing: 20) {
                // SF Symbol for text recognition
                Image("TextClip")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .symbolEffect(.pulse, options: .repeating, value: 1)
                    .padding(.top, 20)

                // Title with modern typography
                Text("Welcome to TextClip")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                // Subtitle with clarity
                Text("Capture and recognize text effortlessly on macOS")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                // Instructions with text.magnifier SF Symbol
                VStack(alignment: .center, spacing: 4) {
                    HStack {
                        Text("Use the menu bar icon")
                        Image(systemName: "text.magnifyingglass")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    Text("in the top-right corner to access TextClip features.")
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

                // Settings section
                VStack(spacing: 10) {
                    Text("Preferences")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 10)

                    // Don't show this again toggle
                    Toggle("Don't show this again", isOn: $dontShowAgain)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 30)
                        .onChange(of: dontShowAgain) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "dontShowAgain")
                        }

                    // Privacy & Security button
                    Button(action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Open Screen Recording Settings")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
                    
                    // Accessibility Settings button
                    Button(action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Open Accessibility Settings")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
                }

                Spacer()

                // Dismiss button
                Button(action: {
                    NSApp.keyWindow?.close()
                }) {
                    Text("Dismiss Window")
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
            }
            .padding()
            .frame(width: 400, height: 450)
            
            // This is the custom sidebar
            if showInfo {
                InfoView()
                    .frame(width: 250)
                    .transition(.move(edge: .trailing))
            }
        }
        // The overall frame of the window will animate when the sidebar appears/disappears
        .frame(width: showInfo ? 650 : 400, height: 450)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    // Use an animation block for a smooth transition
                    withAnimation(.spring()) {
                        showInfo.toggle()
                    }
                }) {
                    Label("Show Info", systemImage: "info.circle")
                }
            }
        }
    }
}


// MARK: - Preview Provider
#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}
