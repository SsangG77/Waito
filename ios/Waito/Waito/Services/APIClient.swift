import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)

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
        }
    }
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    // TODO: 배포 시 실제 서버 URL로 변경
    #if DEBUG
    private let baseURL = "http://localhost:3000"
    #else
    private let baseURL = "https://api.waito.app"
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

    // MARK: - Devices

    func registerDevice(token: String) async throws -> DeviceRegisterResponse {
        try await post("/api/devices/register", body: DeviceRegisterRequest(deviceToken: token))
    }

    // MARK: - Trackings

    func createTracking(
        deviceToken: String,
        carrierId: String,
        trackingNumber: String,
        itemName: String? = nil
    ) async throws -> TrackingCreateResponse {
        try await post("/api/trackings", body: TrackingCreateRequest(
            deviceToken: deviceToken,
            carrierId: carrierId,
            trackingNumber: trackingNumber,
            itemName: itemName
        ))
    }

    func listTrackings(deviceToken: String) async throws -> [TrackingListItem] {
        try await get("/api/trackings?deviceToken=\(deviceToken)")
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
            let message: String
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                message = errorResponse.error
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
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
