//
//  WaitoApp.swift
//  Waito
//
//  Created by 김무경 on 3/17/26.
//

import SwiftUI

@main
struct WaitoApp: App {
    @State private var trackingService = TrackingService()
    @State private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(trackingService)
                .environment(subscriptionManager)
                .preferredColorScheme(.dark)
        }
    }
}
