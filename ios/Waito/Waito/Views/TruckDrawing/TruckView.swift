import SwiftUI

// MARK: - 트럭 메인 렌더링 뷰

struct TruckView: View {
    let config: TruckConfig
    let size: CGFloat

    var body: some View {
        let parts = shapeParts()
        ZStack {
            TruckStyleModifier.apply(style: config.style, path: parts.cargo, color: config.cargoColor.color, size: size)
            TruckStyleModifier.apply(style: config.style, path: parts.box,   color: config.boxColor.color,   size: size)
            TruckStyleModifier.apply(style: config.style, path: parts.head,  color: config.headColor.color,  size: size)
            parts.wheels.fill(Color.black.opacity(0.85))
        }
        .frame(width: size, height: size)
    }

    private func shapeParts() -> TruckParts {
        switch config.shape {
        case .standard: return StandardTruckShape.parts(in: size)
        case .minivan:  return MinivanTruckShape.parts(in: size)
        case .heavy:    return HeavyTruckShape.parts(in: size)
        }
    }
}

// MARK: - Live Activity용 미니 트럭

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
        TruckView(config: TruckConfig(shape: .minivan, style: .pixel, headColor: .orange, cargoColor: .blue, boxColor: .yellow), size: 100)
        TruckView(config: TruckConfig(shape: .heavy, style: .threeD, headColor: .red, cargoColor: .gray, boxColor: .white), size: 120)
    }
    .padding()
    .background(.black)
}
