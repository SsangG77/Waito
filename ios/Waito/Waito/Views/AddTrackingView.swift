import SwiftUI

struct AddTrackingView: View {
    @Environment(TrackingService.self) private var service
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCarrierId = ""
    @State private var trackingNumber = ""
    @State private var itemName = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("택배사") {
                    Picker("택배사 선택", selection: $selectedCarrierId) {
                        Text("선택해주세요").tag("")
                        ForEach(service.carriers) { carrier in
                            Text(carrier.name).tag(carrier.id)
                        }
                    }
                }

                Section("운송장 정보") {
                    TextField("운송장 번호", text: $trackingNumber)
                        .keyboardType(.numberPad)

                    TextField("상품명 (선택)", text: $itemName)
                }
            }
            .navigationTitle("택배 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") {
                        submit()
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
            .task {
                if service.carriers.isEmpty {
                    await service.loadCarriers()
                }
            }
        }
    }

    private var isValid: Bool {
        !selectedCarrierId.isEmpty && !trackingNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        isSubmitting = true
        Task {
            let name = itemName.trimmingCharacters(in: .whitespaces)
            let success = await service.addTracking(
                carrierId: selectedCarrierId,
                trackingNumber: trackingNumber.trimmingCharacters(in: .whitespaces),
                itemName: name.isEmpty ? nil : name,
                limit: subscription.liveActivityLimit
            )
            isSubmitting = false
            if success {
                dismiss()
            }
        }
    }
}

#Preview {
    AddTrackingView()
        .environment(TrackingService())
        .environment(SubscriptionManager())
}
