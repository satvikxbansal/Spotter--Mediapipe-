import Foundation

nonisolated enum BackendMode: String, Codable {
    case local
    case firebase
    case supabase
}
