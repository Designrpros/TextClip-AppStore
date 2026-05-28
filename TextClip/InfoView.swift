//
//  InfoView.swift
//  TextClip
//
//  Created by Vegar Berentsen on 01/07/2025.
//

import SwiftUI
import StoreKit

struct InfoView: View {
    // Environment value to request a review from the App Store.
    @Environment(\.requestReview) var requestReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About the App")
                        .font(.system(.headline, design: .rounded))
                    Text("TextClip is a lightweight utility designed to make capturing and recognizing text from your screen as seamless as possible. It also supports QR code detection.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Use")
                        .font(.system(.headline, design: .rounded))
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Press **Cmd + Shift + 2** to start a capture.", systemImage: "keyboard.fill")
                        Label("Click and drag to select a region.", systemImage: "cursorarrow.and.square.on.square.dashed")
                        Label("Release to copy text or QR code data.", systemImage: "doc.on.clipboard.fill")
                    }
                    .foregroundStyle(.secondary)
                }
                
                // --- NEW SECTION FOR RATING ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enjoying TextClip?")
                        .font(.system(.headline, design: .rounded))
                    
                    Button(action: {
                        // This will present the standard App Store review prompt.
                        // The system decides if and when to show it to avoid spamming the user.
                        requestReview()
                    }) {
                        Text("Rate this App")
                    }
                    .buttonStyle(.link)
                }

                Divider()
                
                VStack(alignment: .center) {
                    Link("Provide Feedback", destination: URL(string: "https://designr.pro/contact")!)
                }
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .center) {
                    Link("Privacy Policy", destination: URL(string: "https://designr.pro/privacy-policy")!)
                }
                .frame(maxWidth: .infinity)
                
            }
            .padding()
        }
    }
}

#Preview {
    InfoView()
}
