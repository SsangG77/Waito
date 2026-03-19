import Foundation
import CoreGraphics

/// Dynamic Island 외곽선을 시계방향으로 따라가는 트럭의 위치와 회전각을 계산
///
/// 경로 구조 (시계방향):
/// ```
///         ④ 상단 직선
///     ③╭━━━━━━━━━━━━━━━━━╮⑤
///      ┃                 ┃
///     ②┃                 ┃⑥
///      ┃                 ┃
///     ①╰━━━━━━━━━━━━━━━━━╯⑦
///         ⑧ 하단 직선
/// ```
struct TruckPathCalculator {

    // MARK: - Dynamic Island 외곽 경로 파라미터

    /// Dynamic Island 영역 (Live Activity expanded view 기준 상대 좌표)
    struct IslandMetrics {
        let rect: CGRect
        let cornerRadius: CGFloat

        /// iPhone 14 Pro / 15 / 16 기본값
        static let standard = IslandMetrics(
            rect: CGRect(x: 0, y: 0, width: 250, height: 36.67),
            cornerRadius: 18.335
        )

        var width: CGFloat { rect.width }
        var height: CGFloat { rect.height }
        var minX: CGFloat { rect.minX }
        var minY: CGFloat { rect.minY }
        var maxX: CGFloat { rect.maxX }
        var maxY: CGFloat { rect.maxY }
        var midX: CGFloat { rect.midX }
    }

    let metrics: IslandMetrics

    init(metrics: IslandMetrics = .standard) {
        self.metrics = metrics
    }

    // MARK: - 경로 구간 비율

    /// 각 구간이 전체 둘레에서 차지하는 비율 (시계방향, 하단 좌측 시작)
    /// ① 하단 좌측 → 좌하 코너  (하단 직선 좌반)
    /// ② 좌하 코너 곡선
    /// ③ 좌측 직선
    /// ④ 좌상 코너 곡선
    /// ⑤ 상단 직선
    /// ⑥ 우상 코너 곡선
    /// ⑦ 우측 직선
    /// ⑧ 우하 코너 곡선
    /// ⑨ 하단 우측 → 하단 중앙 (하단 직선 우반)

    private var straightH: CGFloat { metrics.width - 2 * metrics.cornerRadius }
    private var straightV: CGFloat { metrics.height - 2 * metrics.cornerRadius }
    private var cornerArc: CGFloat { .pi / 2 * metrics.cornerRadius } // 90° 호 길이

    private var perimeter: CGFloat {
        2 * straightH + 2 * straightV + 4 * cornerArc
    }

    // MARK: - 위치 계산

    struct TruckPose {
        let position: CGPoint
        let rotationAngle: Double // radians
    }

    /// t값(0.0~1.0)에 대응하는 트럭 위치와 회전각을 반환
    func pose(at t: CGFloat) -> TruckPose {
        let t = min(max(t, 0), 1)
        let distance = t * perimeter

        // 경로를 9구간으로 나눠서 distance가 어디에 해당하는지 결정
        let segments = buildSegments()
        var accumulated: CGFloat = 0

        for segment in segments {
            let segLength = segment.length
            if accumulated + segLength >= distance || segment === segments.last {
                let local = (distance - accumulated) / segLength
                return segment.pose(at: min(max(local, 0), 1))
            }
            accumulated += segLength
        }

        // fallback (도달 불가)
        return TruckPose(position: CGPoint(x: metrics.midX, y: metrics.maxY), rotationAngle: .pi)
    }

    // MARK: - 경로 구간 모델

    private class PathSegment {
        let length: CGFloat
        private let positionAt: (CGFloat) -> CGPoint
        private let angleAt: (CGFloat) -> Double

        init(length: CGFloat, position: @escaping (CGFloat) -> CGPoint, angle: @escaping (CGFloat) -> Double) {
            self.length = length
            self.positionAt = position
            self.angleAt = angle
        }

        func pose(at localT: CGFloat) -> TruckPose {
            TruckPose(position: positionAt(localT), rotationAngle: angleAt(localT))
        }
    }

    private func buildSegments() -> [PathSegment] {
        let r = metrics.cornerRadius
        let m = metrics

        // 꼭짓점 좌표
        let bottomLeft  = CGPoint(x: m.minX + r, y: m.maxY)
        let topLeft     = CGPoint(x: m.minX + r, y: m.minY)
        let topRight    = CGPoint(x: m.maxX - r, y: m.minY)
        let bottomRight = CGPoint(x: m.maxX - r, y: m.maxY)

        // 코너 중심
        let centerBL = CGPoint(x: m.minX + r, y: m.maxY - r)
        let centerTL = CGPoint(x: m.minX + r, y: m.minY + r)
        let centerTR = CGPoint(x: m.maxX - r, y: m.minY + r)
        let centerBR = CGPoint(x: m.maxX - r, y: m.maxY - r)

        return [
            // ① 하단 직선 좌반: 하단 중앙 → 좌하 코너 시작 (왼쪽으로)
            PathSegment(length: straightH / 2, position: { localT in
                let startX = m.midX
                let endX = bottomLeft.x
                return CGPoint(x: startX + (endX - startX) * localT, y: m.maxY)
            }, angle: { _ in .pi }), // ← 방향 180°

            // ② 좌하 코너 (180° → 270°)
            cornerSegment(center: centerBL, startAngle: .pi / 2, endAngle: .pi, radius: r),

            // ③ 좌측 직선: 하→상
            PathSegment(length: straightV, position: { localT in
                let startY = centerBL.y
                let endY = centerTL.y
                return CGPoint(x: m.minX, y: startY + (endY - startY) * localT)
            }, angle: { _ in 3 * .pi / 2 }), // ↑ 방향 270°

            // ④ 좌상 코너 (270° → 360°)
            cornerSegment(center: centerTL, startAngle: .pi, endAngle: 3 * .pi / 2, radius: r),

            // ⑤ 상단 직선: 좌→우
            PathSegment(length: straightH, position: { localT in
                let startX = topLeft.x
                let endX = topRight.x
                return CGPoint(x: startX + (endX - startX) * localT, y: m.minY)
            }, angle: { _ in 0 }), // → 방향 0°

            // ⑥ 우상 코너 (0° → 90°)
            cornerSegment(center: centerTR, startAngle: 3 * .pi / 2, endAngle: 2 * .pi, radius: r),

            // ⑦ 우측 직선: 상→하
            PathSegment(length: straightV, position: { localT in
                let startY = centerTR.y
                let endY = centerBR.y
                return CGPoint(x: m.maxX, y: startY + (endY - startY) * localT)
            }, angle: { _ in .pi / 2 }), // ↓ 방향 90°

            // ⑧ 우하 코너 (90° → 180°)
            cornerSegment(center: centerBR, startAngle: 0, endAngle: .pi / 2, radius: r),

            // ⑨ 하단 직선 우반: 우하 코너 끝 → 하단 중앙 (왼쪽으로)
            PathSegment(length: straightH / 2, position: { localT in
                let startX = bottomRight.x
                let endX = m.midX
                return CGPoint(x: startX + (endX - startX) * localT, y: m.maxY)
            }, angle: { _ in .pi }), // ← 방향 180°
        ]
    }

    /// 코너 곡선 구간 생성 (시계방향 = 각도 증가)
    /// - Parameters:
    ///   - center: 코너 원 중심
    ///   - startAngle/endAngle: 라운드렉트의 arc 각도 (수학적 각도 기준, 시계방향 좌표계)
    ///   - radius: 코너 반지름
    ///
    /// iOS 좌표계 (y↓)에서 시계방향 회전이므로 각도가 증가하는 방향
    private func cornerSegment(center: CGPoint, startAngle: CGFloat, endAngle: CGFloat, radius: CGFloat) -> PathSegment {
        let arcLength = cornerArc
        let tiltAmount: Double = .pi / 12 // ±15° 기울기 (귀여움 포인트)

        return PathSegment(length: arcLength, position: { localT in
            // iOS 좌표계: y가 아래로 증가
            // 각도를 반전시켜 시계방향으로
            let angle = startAngle + (endAngle - startAngle) * localT
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            return CGPoint(x: x, y: y)
        }, angle: { localT in
            // 접선 방향 = 원 위 점에서의 법선 + 90°
            let angle = startAngle + (endAngle - startAngle) * localT
            let tangent = Double(angle) + .pi / 2

            // 곡선 구간 ±15° 기울기 (중앙에서 최대)
            let tiltPhase = sin(Double(localT) * .pi) // 0→1→0
            let tilt = tiltAmount * tiltPhase
            return tangent + tilt
        })
    }
}
