import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Island 테두리 U자형 Shape
// 시작: 카메라 왼쪽 (TL corner) → ↓ 왼벽 → BL corner → → 하단 → BR corner → ↑ 오른벽 → TR corner
// 카메라 dead zone을 지나지 않는 U자형 열린 경로

struct IslandBorderShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        return p
    }
}

// MARK: - Expanded 테두리 트럭 뷰

struct ExpandedBorderTruckView: View {
    let state: DeliveryAttributes.ContentState

    private let truckSize: CGFloat = 12
    private let cornerRadius: CGFloat = 38
    private let lineWidth: CGFloat = 2

    // 경로 외벽이 뷰 경계와 겹치면 Live Activity가 클리핑함 → pad로 인셋
    private var pad: CGFloat {
        truckSize / 2 + lineWidth + 2
    }

    var body: some View {
        GeometryReader { geo in
            let drawW = max(geo.size.width  - pad * 2, 1)
            let drawH = max(geo.size.height - pad * 2, 1)
            let r = min(cornerRadius, drawH / 2)

            if let primary = state.primary {
                let progress = primary.status.progress
                let pose = islandBorderPose(progress: progress, w: drawW, h: drawH, r: r)

                ZStack {
                    IslandBorderShape(cornerRadius: r)
                        .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)

                    IslandBorderShape(cornerRadius: r)
                        .trim(from: 0, to: progress)
                        .stroke(Color.wPixelOrange,
                                style: StrokeStyle(lineWidth: lineWidth + 0.5, lineCap: .round))

                    CatalogTruckView(
                        cab: state.truckConfig.cab,
                        truckBody: state.truckConfig.body,
                        wheels: state.truckConfig.wheelType,
                        size: truckSize
                    )
                    .rotationEffect(.radians(pose.rotation))
                    .position(x: pose.position.x - 7, y: pose.position.y - 7)

//                    VStack(spacing: 0) {
//                        
//                    }
//                    .frame(width: drawW, height: drawH)
                }
                .frame(width: drawW, height: drawH)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: 84)
        .padding(.horizontal, 2)
        .background(.white)
    }

    // MARK: - 7-segment pose calculator
    // TL arc | ↓ left | BL arc | → bottom | BR arc | ↑ right | TR arc
    // CCW arc (clockwise:true in SwiftUI y-down): dirAngle = α − π/2

    private func islandBorderPose(
        progress: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat
    ) -> (position: CGPoint, rotation: CGFloat) {
        let arcLen = CGFloat.pi / 2 * r
        let s1 = arcLen
        let s2 = max(h - 2*r, 0)
        let s3 = arcLen
        let s4 = max(w - 2*r, 0)
        let s5 = arcLen
        let s6 = max(h - 2*r, 0)
        let s7 = arcLen

        let total = s1 + s2 + s3 + s4 + s5 + s6 + s7
        guard total > 0 else { return (CGPoint(x: w/2, y: h/2), 0) }

        var rem = min(progress, 1) * total

        func arcPose(_ α: CGFloat, _ cx: CGFloat, _ cy: CGFloat) -> (position: CGPoint, rotation: CGFloat) {
            (CGPoint(x: cx + r * cos(α), y: cy + r * sin(α)), α - CGFloat.pi/2)
        }

        func linePose(_ t: CGFloat, _ sx: CGFloat, _ sy: CGFloat,
                      _ ex: CGFloat, _ ey: CGFloat, _ dir: CGFloat) -> (position: CGPoint, rotation: CGFloat) {
            (CGPoint(x: sx + t*(ex-sx), y: sy + t*(ey-sy)), dir)
        }

        if rem < s1 {
            return arcPose(-CGFloat.pi/2 - (rem/s1) * CGFloat.pi/2, r, r)
        }
        rem -= s1

        if s2 > 0, rem < s2 {
            return linePose(rem/s2, 0, r, 0, h-r, CGFloat.pi/2)
        }
        rem -= s2

        if rem < s3 {
            return arcPose(.pi - (rem/s3) * CGFloat.pi/2, r, h-r)
        }
        rem -= s3

        if s4 > 0, rem < s4 {
            return linePose(rem/s4, r, h, w-r, h, 0)
        }
        rem -= s4

        if rem < s5 {
            return arcPose(CGFloat.pi/2 - (rem/s5) * CGFloat.pi/2, w-r, h-r)
        }
        rem -= s5

        if s6 > 0, rem < s6 {
            return linePose(rem/s6, w, h-r, w, r, -CGFloat.pi/2)
        }
        rem -= s6

        let α = -(min(rem, s7) / s7) * CGFloat.pi/2
        return arcPose(α, w-r, r)
    }
}

// MARK: - Previews

private let _expandedPreviewAttr = DeliveryAttributes(deviceId: "preview")

#Preview("ExpandedBorderTruckView — 배송중", as: .dynamicIsland(.expanded), using: _expandedPreviewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState(items: [
        TrackingItemState(
            trackingNumber: "123456789012",
            status: .delivering,
            carrierName: "CJ대한통운",
            itemName: "맥북 프로 14인치",
            estimatedDelivery: "오늘 도착 예정"
        )
    ], truckConfig: .default)
}

#Preview("ExpandedBorderTruckView — 접수", as: .dynamicIsland(.expanded), using: _expandedPreviewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState(items: [
        TrackingItemState(
            trackingNumber: "123456789012",
            status: .registered,
            carrierName: "CJ대한통운",
            itemName: "에어팟 프로",
            estimatedDelivery: nil
        )
    ], truckConfig: .default)
}
