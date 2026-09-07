import SwiftUI
import MapKit

/// 택배가 지나온 위치를 지도에 그린다 (구독자 전용).
///
/// 애플 기본 핀 대신 사용자가 고른 픽셀 트럭이 현재 위치에 선다 — 앱의 주인공을 지도에서도 유지.
/// 지나온 지점은 작은 사각 도트, 경로는 점선으로 잇는다.
struct DeliveryMapView: View {
    let tracking: TrackingListItem
    let onClose: () -> Void

    @State private var mapService = DeliveryMapService()
    @State private var camera: MapCameraPosition = .automatic
    @State private var truckBounce: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var config: TruckConfig { TruckConfigStore.shared.config }
    private var points: [DeliveryMapPoint] { mapService.points }
    private var currentPoint: DeliveryMapPoint? { points.last }

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "MAP", onBack: onClose)

            ZStack {
                if points.isEmpty {
                    emptyState
                } else {
                    map
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .background(Color.bg)
        .task {
            await mapService.load(events: tracking.events ?? [])
            focusOnRoute()
            startTruckBounce()
        }
        .accessibilityIdentifier("delivery_map_view")
    }

    // MARK: - 지도

    private var map: some View {
        Map(position: $camera) {
            // 지나온 경로 — 점선으로 이어 "정확한 주행 경로가 아니라 거쳐 간 지점"임을 드러낸다
            if points.count >= 2 {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(
                        Color.pixelRed,
                        style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [6, 5]),
                    )
            }

            ForEach(points) { point in
                Annotation(point.placeName, coordinate: point.coordinate) {
                    if point.id == currentPoint?.id {
                        truckMarker
                    } else {
                        passedDot
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityIdentifier("delivery_map")
    }

    /// 현재 위치 — 사용자가 꾸민 트럭
    private var truckMarker: some View {
        CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: 46)
            .offset(y: truckBounce)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .accessibilityIdentifier("map_current_truck")
    }

    /// 지나온 지점 — 픽셀 사각 도트
    private var passedDot: some View {
        Rectangle()
            .fill(Color.pixelRed)
            .frame(width: 9, height: 9)
            .overlay(Rectangle().stroke(Color.pixelText, lineWidth: 1.5))
    }

    // MARK: - 하단 정보

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tracking.itemName.isEmpty ? tracking.trackingNumber : tracking.itemName)
                .font(pixelFont(13))
                .foregroundStyle(Color.pixelText)

            if let current = currentPoint {
                HStack(spacing: 6) {
                    Text("현재")
                        .font(pixelFont(11))
                        .foregroundStyle(Color.pixelMuted)
                    Text(current.placeName)
                        .font(pixelFont(12))
                        .foregroundStyle(Color.pixelText)
                }
                Text(current.description)
                    .font(pixelFont(11))
                    .foregroundStyle(Color.pixelMuted)
                    .lineLimit(2)
            }

            if mapService.unresolvedCount > 0 {
                Text("위치 확인 안 됨 \(mapService.unresolvedCount)곳")
                    .font(pixelFont(11))
                    .foregroundStyle(Color.pixelOrange)
                    .accessibilityIdentifier("map_unresolved_notice")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.bg)
        .overlay(Rectangle().fill(Color.pixelBorder).frame(height: 1), alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: 90)
            Text(mapService.isResolving ? "위치 찾는 중" : "아직 확인된 위치가 없어요")
                .font(pixelFont(12))
                .foregroundStyle(Color.pixelText)
            Text("택배사가 위치를 알려주면 지도에 표시돼요")
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelMuted)
        }
        .accessibilityIdentifier("map_empty_state")
    }

    // MARK: - 카메라 / 모션

    /// 지나온 지점이 모두 들어오도록 화면을 맞춘다.
    private func focusOnRoute() {
        guard !points.isEmpty else { return }
        let lats = points.map(\.coordinate.latitude)
        let lons = points.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2,
        )
        // 지점이 하나뿐이면 폭이 0 이라 최소 여백을 준다
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.05),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.05),
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func startTruckBounce() {
        guard !reduceMotion, currentPoint != nil else { return }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            truckBounce = -4
        }
    }
}
