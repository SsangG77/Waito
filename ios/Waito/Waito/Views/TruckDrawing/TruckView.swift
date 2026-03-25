import SwiftUI

// MARK: - 트럭 메인 렌더링 뷰

struct TruckView: View {
    let config: TruckConfig
    let size: CGFloat

    var body: some View {
        let parts = truckParts

        ZStack {
            // 짐칸
            TruckStyleModifier.apply(
                style: config.style,
                path: parts.cargo,
                color: config.cargoColor.color,
                size: size
            )

            // 택배 상자
            TruckStyleModifier.apply(
                style: config.style,
                path: parts.box,
                color: config.boxColor.color,
                size: size
            )

            // 헤드 (운전석)
            TruckStyleModifier.apply(
                style: config.style,
                path: parts.head,
                color: config.headColor.color,
                size: size
            )

            // 바퀴 — 항상 검정
            parts.wheels.fill(Color(white: 0.1))
        }
        .frame(width: size, height: size)
    }

    private var truckParts: TruckParts {
        switch config.shape {
        case .standard: StandardTruckShape.parts(in: size)
        case .minivan:  MinivanTruckShape.parts(in: size)
        case .heavy:    HeavyTruckShape.parts(in: size)
        }
    }
}

// MARK: - Live Activity용 미니 트럭 (SF Symbol 대체)

struct MiniTruckView: View {
    let config: TruckConfig
    let size: CGFloat

    var body: some View {
        TruckView(config: config, size: size)
            .drawingGroup()
    }
}

#Preview {
    VStack(spacing: 20) {
        TruckView(config: .default, size: 80)
        TruckView(
            config: TruckConfig(shape: .minivan, style: .pixel, headColor: .red, cargoColor: .white, boxColor: .yellow),
            size: 80
        )
        TruckView(
            config: TruckConfig(shape: .heavy, style: .threeD, headColor: .green, cargoColor: .gray, boxColor: .purple),
            size: 80
        )
    }
    .padding()
    .background(.black)
}
