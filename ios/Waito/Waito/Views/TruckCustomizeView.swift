import SwiftUI

struct TruckCustomizeView: View {
    @Environment(SubscriptionManager.self) private var subscription
    @Bindable private var store = TruckConfigStore.shared

    @State private var showSubscriptionAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // MARK: - 미리보기
                previewSection

                // MARK: - 트럭 모양
                optionSection(title: "트럭 모양") {
                    HStack(spacing: 12) {
                        ForEach(TruckShape.allCases, id: \.self) { shape in
                            shapeOption(shape)
                        }
                    }
                }

                // MARK: - 그림체
                optionSection(title: "그림체") {
                    HStack(spacing: 12) {
                        ForEach(TruckStyle.allCases, id: \.self) { style in
                            styleOption(style)
                        }
                    }
                }

                // MARK: - 색상 커스텀
                colorSection(title: "헤드 색상", selection: $store.config.headColor)
                colorSection(title: "짐칸 색상", selection: $store.config.cargoColor)
                colorSection(title: "상자 색상", selection: $store.config.boxColor)

                // MARK: - 구독 상태 (디버그)
                #if DEBUG
                debugSubscriptionSection
                #endif
            }
            .padding()
        }
        .navigationTitle("내 트럭")
        .background(Color(.systemGroupedBackground))
        .pixelAlert(
            title: "Waito Plus",
            message: "이 옵션은 Waito Plus 구독이 필요해요.\n월 ₩2,900 / 연 ₩19,900",
            isPresented: $showSubscriptionAlert
        )
    }

    // MARK: - 미리보기

    private var previewSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black)
                    .frame(height: 160)

                TruckView(config: store.config, size: 100)
            }

            Text("미리보기")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 옵션 섹션

    private func optionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                content()
            }
        }
    }

    // MARK: - 트럭 모양 옵션

    private func shapeOption(_ shape: TruckShape) -> some View {
        let isSelected = store.config.shape == shape
        let locked = !subscription.canUse(shape: shape)

        return Button {
            if locked {
                showSubscriptionAlert = true
            } else {
                store.config.shape = shape
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(width: 80, height: 80)

                    TruckView(
                        config: TruckConfig(shape: shape, style: .flat, headColor: .blue, cargoColor: .white, boxColor: .orange),
                        size: 50
                    )

                    if locked {
                        lockOverlay
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )

                Text(shape.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 그림체 옵션

    private func styleOption(_ style: TruckStyle) -> some View {
        let isSelected = store.config.style == style
        let locked = !subscription.canUse(style: style)

        return Button {
            if locked {
                showSubscriptionAlert = true
            } else {
                store.config.style = style
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(width: 80, height: 80)

                    TruckView(
                        config: TruckConfig(shape: .standard, style: style, headColor: .blue, cargoColor: .white, boxColor: .orange),
                        size: 50
                    )

                    if locked {
                        lockOverlay
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )

                Text(style.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 색상 섹션

    private func colorSection(title: String, selection: Binding<TruckColor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(TruckColor.allCases, id: \.self) { truckColor in
                    colorChip(truckColor, isSelected: selection.wrappedValue == truckColor) {
                        if !subscription.canUse(color: truckColor) {
                            showSubscriptionAlert = true
                        } else {
                            selection.wrappedValue = truckColor
                        }
                    }
                }
            }
        }
    }

    private func colorChip(_ truckColor: TruckColor, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let locked = !subscription.canUse(color: truckColor)

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(truckColor.color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2.5)
                            .padding(-3)
                    )

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 잠금 오버레이

    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
    }

    // MARK: - 디버그 구독 토글

    #if DEBUG
    private var debugSubscriptionSection: some View {
        VStack(spacing: 8) {
            Divider()
            Button {
                subscription.toggleSubscription()
            } label: {
                HStack {
                    Image(systemName: subscription.isSubscribed ? "checkmark.circle.fill" : "circle")
                    Text(subscription.isSubscribed ? "구독 중 (디버그)" : "구독 안 함 (디버그)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
    #endif
}

#Preview {
    NavigationStack {
        TruckCustomizeView()
    }
    .environment(SubscriptionManager())
}
