import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
    /// 운송장 조회 불가(NOT_FOUND) — 사용자에게 확인 후 강제 추가 여부를 묻는다
    case trackingNotFound(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다"
        case .serverError(let code, let message):
            return "서버 오류 (\(code)): \(message)"
        case .decodingError(let error):
            return "데이터 파싱 실패: \(error.localizedDescription)"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .trackingNotFound(let message):
            return message
        }
    }
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    // 운영 서버: Vultr 인스턴스에 공인 IP+HTTP 직접 접속(도메인/HTTPS 미사용, ATS 전체 허용 전제)
    // brawlytics가 3000 사용 중 → Waito는 3001
    #if DEBUG
    private let baseURL = "http://192.168.31.189:3000"
    #else
    private let baseURL = "http://158.247.223.154:3001"
    #endif

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// 쿼리스트링 값 percent-encoding (현재 UUID 라 무변화이나 토큰 형식이 바뀌어도 안전)
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
    private func q(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? value
    }

    // MARK: - Devices

    func registerDevice(token: String) async throws -> DeviceRegisterResponse {
        try await post("/api/devices/register", body: DeviceRegisterRequest(deviceToken: token))
    }

    // MARK: - Trackings

    func createTracking(
        deviceToken: String,
        carrierId: String,
        trackingNumber: String,
        itemName: String? = nil,
        memo: String? = nil,
        force: Bool = false
    ) async throws -> TrackingCreateResponse {
        try await post("/api/trackings", body: TrackingCreateRequest(
            deviceToken: deviceToken,
            carrierId: carrierId,
            trackingNumber: trackingNumber,
            itemName: itemName,
            memo: memo,
            force: force
        ))
    }

    /// 품명/메모 수정 (PUT /api/trackings/:id) — 수정된 항목을 반환
    func updateTracking(id: Int, itemName: String?, memo: String?) async throws -> TrackingListItem {
        try await put("/api/trackings/\(id)", body: TrackingUpdateRequest(itemName: itemName, memo: memo))
    }

    /// 디바이스 진행도(배송완료 포인트 + 해제 부품) 조회
    func getDeviceProgress(deviceToken: String) async throws -> DeviceProgress {
        try await get("/api/devices/me?deviceToken=\(q(deviceToken))")
    }

    /// 포인트로 부품 1개 해제 — 갱신된 진행도 반환
    func unlockPart(deviceToken: String, part: String) async throws -> DeviceProgress {
        try await post("/api/devices/unlock-part", body: UnlockPartRequest(deviceToken: deviceToken, part: part))
    }

    /// 표준 원격알림(일반 배너)용 APNs device token 등록
    func registerAPNsToken(deviceToken: String, apnsToken: String) async throws {
        let _: SuccessResponse = try await put(
            "/api/devices/apns-token",
            body: APNsTokenRegisterRequest(deviceToken: deviceToken, apnsToken: apnsToken)
        )
    }

    func listTrackings(deviceToken: String) async throws -> [TrackingListItem] {
        try await get("/api/trackings?deviceToken=\(q(deviceToken))")
    }

    func getTracking(id: Int) async throws -> TrackingDetail {
        try await get("/api/trackings/\(id)")
    }

    func deleteTracking(id: Int) async throws {
        let _: EmptyResponse = try await delete("/api/trackings/\(id)")
    }

    func refreshTracking(id: Int) async throws -> TrackingListItem {
        try await post("/api/trackings/\(id)/refresh", body: EmptyBody())
    }

    func updatePushToken(trackingId: Int, pushToken: String) async throws {
        let _: SuccessResponse = try await put(
            "/api/trackings/\(trackingId)/push-token",
            body: PushTokenUpdateRequest(pushToken: pushToken)
        )
    }

    /// push-to-start 토큰 + 트럭 설정을 디바이스 단위로 등록
    func registerPushToStartToken(deviceToken: String, pushToStartToken: String, truckConfig: TruckConfig) async throws {
        let _: SuccessResponse = try await put(
            "/api/devices/push-to-start-token",
            body: PushToStartTokenRequest(
                deviceToken: deviceToken,
                pushToStartToken: pushToStartToken,
                truckConfig: truckConfig
            )
        )
    }

    // MARK: - Carriers

    func getCarriers() async throws -> [Carrier] {
        try await get("/api/carriers")
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = try buildRequest(path: path, method: "POST")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = try buildRequest(path: path, method: "PUT")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE")
        return try await perform(request)
    }

    // MARK: - Helpers

    private func buildRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        // 204 No Content
        if httpResponse.statusCode == 204 {
            if let empty = EmptyResponse() as? T {
                return empty
            }
        }

        // 4xx / 5xx
        if httpResponse.statusCode >= 400 {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)

            // 운송장 조회 불가 → 확인 다이얼로그용 전용 에러
            if httpResponse.statusCode == 422, errorResponse?.error == "TRACKING_NOT_FOUND" {
                throw APIError.trackingNotFound(
                    message: errorResponse?.message ?? "운송장을 조회할 수 없습니다."
                )
            }

            let message = errorResponse?.error ?? (String(data: data, encoding: .utf8) ?? "Unknown error")
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Helper Types

private struct EmptyBody: Encodable {}

struct EmptyResponse: Decodable {
    init() {}
}

struct SuccessResponse: Decodable {
    let success: Bool
}
