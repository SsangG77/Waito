import Foundation

/// 마지막으로 받은 택배 목록을 기기에 저장한다.
/// 앱 시작 때 서버 응답을 기다리지 않고 먼저 보여주기 위한 용도라, 읽기/쓰기 실패는 조용히 무시한다.
enum TrackingListCache {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tracking_list_cache.json")
    }

    static func load() -> [TrackingListItem] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TrackingListItem].self, from: data)) ?? []
    }

    static func save(_ items: [TrackingListItem]) {
        guard let url = fileURL else { return }
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
