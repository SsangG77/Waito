import SwiftUI

// MARK: - 그림체 적용

struct TruckStyleModifier {

    @ViewBuilder
    static func apply(style: TruckStyle, path: Path, color: Color, size: CGFloat) -> some View {
        switch style {
        case .flat:
            flatStyle(path: path, color: color)
        case .pixel:
            pixelStyle(path: path, color: color, size: size)
        case .threeD:
            threeDStyle(path: path, color: color)
        }
    }

    // MARK: - Flat (깔끔한 단색 + 얇은 테두리)

    private static func flatStyle(path: Path, color: Color) -> some View {
        ZStack {
            path.fill(color)
            path.stroke(color.opacity(0.4), lineWidth: 0.5)
        }
    }

    // MARK: - Pixel (도트 아트 — 격자 + 밝기 변형으로 질감)

    private static func pixelStyle(path: Path, color: Color, size: CGFloat) -> some View {
        let bounds = path.boundingRect
        let pixelSize = max(floor(size / 8), 2)
        let gap: CGFloat = 0.8

        return Canvas { context, _ in
            let cols = Int(ceil(bounds.width / pixelSize))
            let rows = Int(ceil(bounds.height / pixelSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let cx = bounds.minX + CGFloat(col) * pixelSize + pixelSize / 2
                    let cy = bounds.minY + CGFloat(row) * pixelSize + pixelSize / 2

                    guard path.contains(CGPoint(x: cx, y: cy)) else { continue }

                    // 체커보드 밝기 변형으로 질감
                    let isDark = (row + col) % 2 == 0
                    let opacity: Double = isDark ? 0.85 : 1.0

                    let rect = CGRect(
                        x: bounds.minX + CGFloat(col) * pixelSize + gap / 2,
                        y: bounds.minY + CGFloat(row) * pixelSize + gap / 2,
                        width: pixelSize - gap,
                        height: pixelSize - gap
                    )
                    context.fill(
                        Path(rect),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
        .frame(width: bounds.maxX, height: bounds.maxY)
    }

    // MARK: - 3D (하이라이트 + 그라데이션 + 그림자 + 아웃라인)

    private static func threeDStyle(path: Path, color: Color) -> some View {
        ZStack {
            // 그림자 레이어
            path.fill(Color.black.opacity(0.3))
                .offset(x: 1, y: 2)

            // 메인 그라데이션
            path.fill(
                LinearGradient(
                    colors: [
                        color.opacity(1.0),
                        color.opacity(0.7),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // 하이라이트 (상단 밝은 줄)
            path.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )

            // 아웃라인
            path.stroke(Color.black.opacity(0.25), lineWidth: 0.8)
        }
    }
}
