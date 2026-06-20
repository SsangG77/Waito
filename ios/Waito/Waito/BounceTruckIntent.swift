import AppIntents
import ActivityKit

/// 바운스 중복 실행 방지 게이트. (버튼을 연타해도 진행 중엔 무시)
actor BounceGate {
    static let shared = BounceGate()
    private var running = false
    /// 시작 가능하면 true 를 돌려주고 잠근다. 이미 진행 중이면 false.
    func tryBegin() -> Bool {
        if running { return false }
        running = true
        return true
    }
    func end() { running = false }
}

/// 잠금화면 Live Activity 의 "> BOUNCE" 버튼이 실행하는 인텐트.
/// Live Activity 버튼은 클로저가 아니라 AppIntent 로만 동작한다(iOS 17+, LiveActivityIntent).
/// 트럭 y 오프셋(truckBounce)을 단계별로 갱신해 "한 번 위→아래" 홉을 만든다.
/// 위젯이 이 값에 `.animation(nil)` 을 줘서 보간 없이 스냅 → 8비트 게임처럼 끊기는 모션.
struct BounceTruckIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "트럭 바운스"
    static var description = IntentDescription("잠금화면 트럭을 한 번 위아래로 튕긴다.")

    func perform() async throws -> some IntentResult {
        // 진행 중이면 무시(버튼 무반응). 끝나면 해제.
        guard await BounceGate.shared.tryBegin() else { return .result() }

        if let activity = Activity<DeliveryAttributes>.activities.first {
            let base = activity.content.state            // items/truckConfig 유지
            // 한 번 위→아래. 보간 없이 스냅되므로 단계가 곧 8비트 프레임.
            let frames: [Double] = [-7, -14, -7, 0]
            for y in frames {
                var state = base
                state.truckBounce = y
                await activity.update(.init(state: state, staleDate: nil))
                try? await Task.sleep(nanoseconds: 90_000_000)   // 0.09s 프레임 유지
            }
        }

        await BounceGate.shared.end()
        return .result()
    }
}
