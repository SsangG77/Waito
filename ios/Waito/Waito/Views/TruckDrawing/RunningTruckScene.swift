import SwiftUI

// MARK: - Color(hex: UInt32) 헬퍼
// 앱 타깃의 Color(hex: String) 와는 인자 타입이 달라 오버로드로 공존한다.
// (위젯 타깃엔 Color(hex: String) 가 없으므로 여기 정의가 단독으로 쓰인다.)
extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

// MARK: - 달리는 트럭 효과 (재사용 래퍼)

/// 임의의 트럭 View 를 받아 "달리는 것처럼" 보이게 하는 모션 래퍼.
/// 트럭 자체(합성/크기/이미지)는 주입받은 `truck()` 이 전적으로 책임진다.
/// - 트럭을 가운데 두고 위아래 바운스.
/// - 속도선이 오른쪽 밖 → 왼쪽 밖으로 흘러 속도감을 만든다(앞/뒤 레이어 패럴랙스).
/// 가용 공간(GeometryReader)에 맞춰 스스로 크기를 잡으므로
/// 다이나믹 아일랜드 접힘/펼침, 라이브 액티비티 등 어디서든 그대로 쓸 수 있다.
///
/// 사용 예:
/// ```
/// RunningTruckView(lineCount: 6) {
///     CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 24)
/// }
/// .frame(width: 30, height: 24)
/// ```
struct RunningTruckView<Truck: View>: View {
    /// 속도선 개수(0 이면 바운스만). 작은 영역은 적게(4~8), 넓은 영역은 16 안팎 권장.
    var lineCount: Int = 16
    /// 위로 튀어오르는 높이(pt).
    var bounce: CGFloat = 6
    /// 바운스 한 박자 시간(8비트 느낌의 짧고 끊기는 점프).
    var bouncePeriod: Double = 0.17
    /// 노랑 속도선 색.
    var accent: Color = Color(hex: 0xffd166)
    /// true = 바운스+속도선이 실제로 움직임(인앱/프리뷰). false = 정적 "달리는 포즈"(속도선 고정).
    /// Live Activity(잠금화면/DI)는 iOS가 연속 SwiftUI 애니메이션을 막으므로 false 로 둔다.
    var animated: Bool = true
    @ViewBuilder var truck: () -> Truck

    private let lines: [SpeedLineSpec]

    init(
        lineCount: Int = 16,
        bounce: CGFloat = 6,
        bouncePeriod: Double = 0.17,
        accent: Color = Color(hex: 0xffd166),
        animated: Bool = true,
        @ViewBuilder truck: @escaping () -> Truck
    ) {
        self.lineCount = lineCount
        self.bounce = bounce
        self.bouncePeriod = bouncePeriod
        self.accent = accent
        self.animated = animated
        self.truck = truck
        self.lines = makeSpeedLines(count: lineCount)
    }

    var body: some View {
        // 공유 시간축(TimelineView)에서 모든 선의 위치를 위상으로 계산한다.
        // → 각 선이 항상 화면 전체에 고르게 퍼져 우 → 좌로 흐른다(뭉침 없음).
        // 정적 모드(animated == false)는 시간 0 스냅샷 한 장을 그린다.
        if animated {
            TimelineView(.animation) { context in
                scene(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            scene(time: 0)
        }
    }

    private func scene(time t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 뒤 레이어 속도선 (트럭 뒤)
                ForEach(lines.filter { !$0.front }) { spec in
                    lineView(spec, w: w, h: h, t: t)
                }

                // 트럭 (가운데 + 제자리 바운스)
                truck()
                    .offset(y: bounceOffset(t: t))

                // 앞 레이어 속도선 (트럭 앞)
                ForEach(lines.filter { $0.front }) { spec in
                    lineView(spec, w: w, h: h, t: t)
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// 8비트 느낌의 짧은 제자리 점프(위로만). 정적 모드는 0.
    private func bounceOffset(t: Double) -> CGFloat {
        guard animated, bounce > 0 else { return 0 }
        // |sin| 주기 = bouncePeriod*2 (올라갔다 내려오는 한 박자).
        let phase = abs(sin(t * .pi / (bouncePeriod * 2)))
        return -bounce * CGFloat(phase)
    }

    /// 속도선 1개 — 위상(phase)으로 우 → 좌 무한 흐름. 위상이 선마다 균등 분배돼 뭉치지 않는다.
    private func lineView(_ spec: SpeedLineSpec, w: CGFloat, h: CGFloat, t: Double) -> some View {
        let length = max(6, spec.lengthFraction * w)
        let travel = w + length * 2                    // 오른쪽 밖 → 왼쪽 밖 총 이동거리
        // p: 0(오른쪽 진입) → 1(왼쪽 퇴장). animated 면 시간으로, 아니면 위상 스냅샷.
        let p = animated
            ? ((t / spec.duration) + spec.phase).truncatingRemainder(dividingBy: 1)
            : spec.phase
        let x = (w + length) - CGFloat(p) * travel
        return Rectangle()
            .fill(spec.yellow ? accent : Color.white)
            .frame(width: length, height: spec.thickness)
            .opacity(spec.opacity)
            .position(x: x, y: spec.y * h)
    }
}

// MARK: - 속도선 스펙

private struct SpeedLineSpec: Identifiable {
    let id: Int
    let y: CGFloat              // 0~1 (세로 위치 비율)
    let lengthFraction: CGFloat // 씬 폭 대비 길이 비율 (작은 영역에도 자동 적응)
    let thickness: CGFloat      // 1.5~3
    let duration: Double        // 한 번 가로지르는 시간(작을수록 빠름)
    let phase: Double           // 0~1 시작 위상 (선마다 달라 균등 분배)
    let opacity: Double
    let front: Bool             // true = 트럭 앞 레이어
    let yellow: Bool            // true = 노랑, false = 흰색
}

/// 인덱스 기반 결정적 생성 — 매 프레임 재계산돼도 스펙이 흔들리지 않는다.
private func makeSpeedLines(count: Int) -> [SpeedLineSpec] {
    func frac(_ n: Int, _ salt: Int) -> Double {
        Double((n &* 2654435761 &+ salt &* 40503) & 0xFFFF) / 65535.0
    }
    return (0..<max(0, count)).map { i in
        SpeedLineSpec(
            id: i,
            y: CGFloat(0.06 + frac(i, 1) * 0.88),
            lengthFraction: CGFloat(0.10 + frac(i, 2) * 0.50),
            thickness: CGFloat(1.5 + frac(i, 3) * 1.5),
            duration: 0.9 + frac(i, 4) * 1.1,   // 0.9~2.0s 가로지르기
            phase: frac(i, 5),                   // 0~1 균등 분배
            opacity: 0.35 + frac(i, 6) * 0.55,
            front: frac(i, 7) < 0.35,
            yellow: frac(i, 8) < (1.0 / 7.0)
        )
    }
}

// MARK: - Preview

#Preview {
    RunningTruckView(lineCount: 16) {
        CatalogTruckView(cab: .truckSoftBlue, truckBody: .truckExpressBlack, wheels: .standard, size: 160)
    }
    .frame(width: 320, height: 200)
    .background(Color(hex: 0x0d1828))
}
