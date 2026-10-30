import Foundation

/// 收藏：只存规则 id（“仓库 + 文件路径”，索引刷新后不变），存在 UserDefaults。
/// 不需要处理孤儿数据：仓库被删后，它的收藏条目自然对不上任何现有条目，
/// 也就不显示；仓库加回来后，同一批 id 又对上了，收藏自动恢复。
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<String> = []

    private let key = "rulesearch.favorites.v1"

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
