import Foundation

/// The endpoint sends timestamps like `2026-08-21T15:09:59.959400+00:00`:
/// six fractional digits and a colon separated offset. `JSONDecoder.iso8601`
/// rejects fractional seconds outright, so we parse with an explicit pair of
/// formatters and fall back to the non fractional form.
public enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }

    public static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// A decoder configured for this endpoint's shape.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized timestamp: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.string(from: date))
        }
        return encoder
    }
}
