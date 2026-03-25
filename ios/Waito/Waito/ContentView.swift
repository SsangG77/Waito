//
//  ContentView.swift
//  Waito
//
//  Created by 김무경 on 3/17/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(TrackingService.self) private var service

    var body: some View {
        TabView {
            Tab("내 택배", systemImage: "box.truck.fill") {
                NavigationStack {
                    DeliveryListView()
                }
            }

            Tab("내 트럭", systemImage: "paintbrush.fill") {
                NavigationStack {
                    TruckCustomizeView()
                }
            }
        }
        .task {
            await service.loadCarriers()
            if service.deviceToken == nil {
                await service.registerDevice(token: UUID().uuidString)
            }
            await service.loadTrackings()
        }
    }
}

#Preview {
    ContentView()
        .environment(TrackingService())
        .environment(SubscriptionManager())
}
