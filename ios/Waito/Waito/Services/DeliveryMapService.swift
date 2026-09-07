import Foundation
import Observation
import CoreLocation

/// 배송 이력 → 지도 지점 변환.
///
/// 좌표 출처는 두 갈래다.
/// 1. 서버가 이미 채워준 좌표 — 국내는 허브 대응표(카카오), 해외는 17TRACK 응답.
/// 2. 좌표가 없는 지점은 위치 이름을 애플 지오코딩으로 변환(기기에서 처리, 결과는 캐시).
///
/// 둘 다 실패한 지점은 핀을 그리지 않고 개수만 알려준다 — 엉뚱한 곳에 찍는 것보다 낫다.
@MainActor
@Observable
final class DeliveryMapService {
    private(set) var points: [DeliveryMapPoint] = []
    /// 위치 이름은 있는데 좌표를 못 구한 지점 수
    private(set) var unresolvedCount = 0
    private(set) var isResolving = false

    /// 지오코딩 결과 캐시 키(위치 이름 → [위도, 경도]). 실패한 이름은 빈 배열로 남겨 재시도를 막는다.
    private static let cacheKey = "waito_geocode_cache"

    private let geocoder = CLGeocoder()

    /// 한 화면에서 지오코딩할 최대 개수. 애플 지오코딩은 호출이 잦으면 차단된다.
    private let geocodeLimit = 12

    func load(events: [TrackingEvent]) async {
        isResolving = true
        defer { isResolving = false }

        var resolved: [DeliveryMapPoint] = []
        var missing = 0
        var cache = Self.loadCache()
        var geocodeBudget = geocodeLimit

        for event in events {
            guard let name = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }

            if let coordinate = event.coordinate {
                resolved.append(makePoint(event, name: name, coordinate: coordinate))
                continue
            }

            if let cached = cache[name] {
                if let coordinate = Self.coordinate(from: cached) {
                    resolved.append(makePoint(event, name: name, coordinate: coordinate))
                } else {
                    missing += 1   // 이전에 변환 실패로 기록된 이름
                }
                continue
            }

            guard geocodeBudget > 0 else {
                missing += 1
                continue
            }
            geocodeBudget -= 1

            let coordinate = await geocode(name)
            cache[name] = coordinate.map { [$0.latitude, $0.longitude] } ?? []
            if let coordinate {
                resolved.append(makePoint(event, name: name, coordinate: coordinate))
            } else {
                missing += 1
            }
        }

        Self.saveCache(cache)
        points = resolved
        unresolvedCount = missing
    }

    // MARK: - 내부

    private func makePoint(
        _ event: TrackingEvent,
        name: String,
        coordinate: CLLocationCoordinate2D,
    ) -> DeliveryMapPoint {
        DeliveryMapPoint(
            id: event.id,
            coordinate: coordinate,
            placeName: name,
            description: event.description,
            time: event.eventTime,
        )
    }

    private func geocode(_ name: String) async -> CLLocationCoordinate2D? {
        do {
            let placemarks = try await geocoder.geocodeAddressString(name)
            return placemarks.first?.location?.coordinate
        } catch {
            return nil
        }
    }

    private static func coordinate(from values: [Double]) -> CLLocationCoordinate2D? {
        guard values.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
    }

    private static func loadCache() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [Double]] ?? [:]
    }

    private static func saveCache(_ cache: [String: [Double]]) {
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }
}
