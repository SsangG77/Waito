import SwiftUI

// MARK: - 예제 뷰

struct PixelExampleView: View {
    @State private var courier = ""
    @State private var trackingNo = ""
    @State private var itemName = ""

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    formCard
                        .padding(16)
                }
            }
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 10) {
            // 뒤로가기
            HStack(spacing: 4) {
                Text("[")
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .bold))
                Text("]")
            }
            .font(pixelFont(10))
            .foregroundStyle(Color.pixelText)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .pixelBox()

            // 타이틀
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.pixelOrange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DELIVERY")
                        .font(pixelFont(13))
                        .foregroundStyle(Color.pixelText)
                    Text("TRACKING SYSTEM")
                        .font(pixelFont(7))
                        .foregroundStyle(Color.pixelMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pixelBox()
        }
        .padding(16)
    }

    // MARK: - 폼 카드

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ADD PARCEL")
                .font(pixelFont(13))
                .foregroundStyle(Color.pixelOrange)

            PixelTextField(label: "COURIER", text: $courier)
            PixelTextField(label: "TRACKING NO.", text: $trackingNo)
            PixelTextField(label: "ITEM NAME", text: $itemName)

            PixelButton(title: "ADD") {}
                .padding(.top, 4)
        }
        .padding(20)
        .pixelBox(border: Color.pixelBorder.opacity(0.5), bg: Color.pixelSurface.opacity(0.4))
    }
}

#Preview {
    PixelExampleView()
}
