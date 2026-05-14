import FirebaseFirestore
import Foundation

nonisolated enum FirestoreEncodingHelpers {
    static func payload<T: Encodable>(from dto: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(dto)
        let object = try JSONSerialization.jsonObject(with: data)
        guard var payload = normalizeJSONValue(object) as? [String: Any] else {
            throw RepositoryError.invalidPayload("Encoded DTO was not a Firestore document payload.")
        }

        for key in nilServerTimestampKeys(in: dto) {
            if payload[key] == nil || payload[key] is NSNull {
                payload[key] = FieldValue.serverTimestamp()
            }
        }

        try FirestorePrivacyValidator.validate(payload)
        return payload
    }

    private static func nilServerTimestampKeys(in dto: Any) -> [String] {
        Mirror(reflecting: dto).children.compactMap { child in
            guard let label = child.label, label.hasPrefix("server") else { return nil }
            return isNilOptional(child.value) ? label : nil
        }
    }

    private static func isNilOptional(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    private static func normalizeJSONValue(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = normalizeJSONValue(pair.value)
            }
        }

        if let array = value as? [Any] {
            return array.map(normalizeJSONValue)
        }

        if let string = value as? String, isUUIDString(string) {
            return string.lowercased()
        }

        return value
    }

    private static func isUUIDString(_ string: String) -> Bool {
        let pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }
}
