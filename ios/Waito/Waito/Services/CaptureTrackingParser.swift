import Foundation
import Vision
import ImageIO

// 캡처(카톡·문자 배송 알림 스크린샷)에서 택배 정보를 추출하는 온디바이스 OCR 파서.
// Apple Vision(VNRecognizeTextRequest) 사용 — 서버 전송 없음(프라이버시), 오프라인 동작.
// Service 규칙: SwiftUI/UIKit 비의존 (CGImage 는 CoreGraphics/ImageIO 로 생성).

/// 캡처에서 추출한 택배 정보. 셋 다 Optional — 있는 것만 Add 폼에 채운다.
struct CapturedTrackingInfo {
    var trackingNumber: String?
    var carrierId: String?     // 앱/서버 공용 택배사 id (cj·hanjin·lotte·epost·logen·coupang)
    var itemName: String?

    var hasAnyInfo: Bool { trackingNumber != nil || carrierId != nil || itemName != nil }
}

enum CaptureTrackingParser {

    /// 이미지 데이터 → OCR → 운송장/택배사/상품명 추출
    static func parse(imageData: Data) async -> CapturedTrackingInfo {
        guard let cgImage = makeCGImage(from: imageData) else { return CapturedTrackingInfo() }
        let lines = await recognizeTextLines(cgImage: cgImage)
        return extract(from: lines)
    }

    /// 복사한 텍스트(클립보드 등) → 운송장/택배사/상품명 추출. OCR 없이 라인 파서만 재사용.
    static func parse(text: String) -> CapturedTrackingInfo {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return extract(from: lines)
    }

    // MARK: - 이미지 디코딩 (UIKit 비의존)

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - OCR (Vision)

    private static func recognizeTextLines(cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            // perform 은 동기 호출 — 요청 생성부터 수행까지 전부 백그라운드 큐 안에서 처리
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ko-KR", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])

                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
        }
    }

    // MARK: - 추출 규칙

    /// 택배사 키워드 → 앱 carrier id (순서 = 우선순위)
    private static let carrierKeywords: [(keywords: [String], id: String)] = [
        (["cj대한통운", "대한통운", "cj 대한통운", "cjlogistics"], "cj"),
        (["한진택배", "한진"], "hanjin"),
        (["롯데택배", "롯데글로벌", "롯데"], "lotte"),
        (["우체국택배", "우체국", "epost"], "epost"),
        (["로젠택배", "로젠"], "logen"),
        (["쿠팡"], "coupang"),
    ]

    /// 운송장 후보 근처에 있으면 가점을 주는 키워드
    private static let trackingHintKeywords = ["운송장", "송장", "등기", "번호", "track", "invoice"]

    /// 상품명 라벨 키워드
    private static let itemNameKeywords = ["상품명", "품명", "주문상품", "상품 명"]

    static func extract(from lines: [String]) -> CapturedTrackingInfo {
        var info = CapturedTrackingInfo()
        let joinedLower = lines.joined(separator: "\n").lowercased()

        // 1) 택배사 — 키워드 매칭
        for entry in carrierKeywords where entry.keywords.contains(where: { joinedLower.contains($0) }) {
            info.carrierId = entry.id
            break
        }

        // 2) 운송장 번호 — 숫자(하이픈 허용) 10~14자리 후보 중 스코어 최고를 채택
        var best: (number: String, score: Int)?
        for line in lines {
            let lineLower = line.lowercased()
            let hintScore = trackingHintKeywords.contains(where: { lineLower.contains($0) }) ? 2 : 0

            for match in candidateNumberRuns(in: line) {
                let digits = match.filter(\.isNumber)
                guard (10...14).contains(digits.count) else { continue }
                // 휴대폰 번호(010-xxxx-xxxx) 오인 방지
                if digits.count == 11 && digits.hasPrefix("010") { continue }

                let score = hintScore + (digits.count >= 12 ? 1 : 0)
                if best == nil || score > best!.score {
                    best = (digits, score)
                }
            }
        }
        info.trackingNumber = best?.number

        // 3) 상품명 — "상품명: xxx" 라벨 라인(또는 라벨 다음 라인)
        outer: for (index, line) in lines.enumerated() {
            for keyword in itemNameKeywords where line.contains(keyword) {
                var value = line
                if let range = value.range(of: keyword) {
                    value = String(value[range.upperBound...])
                }
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: " :：-\t"))
                if value.isEmpty, index + 1 < lines.count {
                    value = lines[index + 1].trimmingCharacters(in: .whitespaces)
                }
                if !value.isEmpty {
                    info.itemName = value
                    break outer
                }
            }
        }

        return info
    }

    /// 라인에서 숫자·하이픈 연속 구간(양끝 숫자)을 추출
    private static func candidateNumberRuns(in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[0-9][0-9\\-]{8,16}[0-9]") else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap {
            Range($0.range, in: line).map { String(line[$0]) }
        }
    }
}
