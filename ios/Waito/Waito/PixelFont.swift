import SwiftUI

// MARK: - Pixel Font (앱 · 위젯 공유)

/// 공용 픽셀 폰트 헬퍼. 이 함수를 쓰는 모든 곳이 동일한 도트 픽셀 폰트(Galmuri9)를 적용받는다.
/// 앱 타깃과 위젯 타깃 모두 이 한 정의를 공유한다(중복 정의 금지).
///
/// ⚠️ Galmuri9 는 단일 weight(Regular) 라 `weight` 인자는 기존 호출부 호환을 위해 남겨두되
///    실제 굵기 변화는 없다(픽셀 폰트 특성). 또렷한 도트를 위해 정수 크기 사용 권장.
func pixelFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .custom("Galmuri9-Regular", size: size)
}
