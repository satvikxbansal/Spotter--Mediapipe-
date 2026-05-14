import Foundation

nonisolated enum FirestorePrivacyValidator {
    private static let maxAllowedDataBytes = 4 * 1_024
    private static let forbiddenKeyNames: Set<String> = [
        "rawvideo",
        "videoframe",
        "cameraframe",
        "faceimage",
        "rawposestream",
        "rawposetimeline",
        "rawlandmarks",
        "rawfaceblendshapestream",
        "biometricfacedata",
        "imagedata",
        "pixelbuffer",
        "apikey",
        "privatekey",
        "serviceaccount",
        "bearertoken"
    ]

    private static let secretPatterns: [NSRegularExpression] = [
        regex("AIza[0-9A-Za-z\\-_]{35}"),
        regex("-----BEGIN [A-Z ]*(?:PRIVATE KEY|KEY|CERTIFICATE)?-----"),
        regex("(?i)\"type\"\\s*:\\s*\"service_account\""),
        regex("(?i)\"private_key_id\"\\s*:"),
        regex("(?i)\"private_key\"\\s*:"),
        regex("(?i)bearer\\s+[A-Za-z0-9._\\-]{20,}"),
        regex("(?i)(api[_-]?key|secret|token|authorization|client[_-]?secret)\\s*[:=]\\s*[\"'][A-Za-z0-9_./+=:\\-]{24,}[\"']")
    ]

    static func validate(_ payload: [String: Any]) throws {
        try validateValue(payload, path: [])
    }

    private static func validateValue(_ value: Any, path: [String]) throws {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = normalizedKeyName(key)
                if forbiddenKeyNames.contains(normalizedKey) {
                    throw RepositoryError.invalidPayload("Payload contains forbidden field: \(key).")
                }
                try validateValue(nestedValue, path: path + [key])
            }
            return
        }

        if let array = value as? [Any] {
            for (index, nestedValue) in array.enumerated() {
                try validateValue(nestedValue, path: path + ["[\(index)]"])
            }
            return
        }

        if let data = value as? Data {
            guard data.count <= maxAllowedDataBytes else {
                throw RepositoryError.invalidPayload("Payload contains a large binary value.")
            }
            return
        }

        if let string = value as? String, containsSecretLikeValue(string) {
            throw RepositoryError.invalidPayload("Payload contains a secret-like string.")
        }
    }

    private static func normalizedKeyName(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func containsSecretLikeValue(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return secretPatterns.contains { pattern in
            pattern.firstMatch(in: string, options: [], range: range) != nil
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid Firestore privacy regex.")
        }
        return expression
    }
}
