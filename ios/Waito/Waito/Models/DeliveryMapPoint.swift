import Foundation
import CoreLocation

/// 지도에 찍는 배송 지점 하나. 배송 이력 이벤트 중 좌표를 확보한 것만 만들어진다.
struct DeliveryMapPoint: Identifiable, Equatable {
    let id: Int              // 원본 이벤트 id
    let coordinate: CLLocationCoordinate2D
    let placeName: String    // 허브명 등 위치 이름
    let description: String  // 택배사 원본 메시지
    let time: String         // 이벤트 시각(서버 문자열 그대로)

    static func == (lhs: DeliveryMapPoint, rhs: DeliveryMapPoint) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
