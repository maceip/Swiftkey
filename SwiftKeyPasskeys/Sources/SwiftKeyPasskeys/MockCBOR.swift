import Foundation

/// Fixed, definite-length canonical CBOR output. No input parsing or dynamic key material.
internal indirect enum MockCBOR {
    case integer(Int), bytes(Data), text(String), map([(MockCBOR, MockCBOR)])

    func encoded() -> Data {
        switch self {
        case .integer(let value): return Self.head(major: value >= 0 ? 0 : 1, count: value >= 0 ? value : -1 - value)
        case .bytes(let bytes): return Self.head(major: 2, count: bytes.count) + bytes
        case .text(let text): let bytes = Data(text.utf8); return Self.head(major: 3, count: bytes.count) + bytes
        case .map(let entries):
            let encoded = entries.map { ($0.encoded(), $1.encoded()) }.sorted {
                $0.0.count == $1.0.count ? $0.0.lexicographicallyPrecedes($1.0) : $0.0.count < $1.0.count
            }
            return encoded.reduce(into: Self.head(major: 5, count: entries.count)) { $0.append($1.0); $0.append($1.1) }
        }
    }
    private static func head(major: UInt8, count: Int) -> Data {
        precondition((0...65_535).contains(count))
        if count < 24 { return Data([(major << 5) | UInt8(count)]) }
        if count < 256 { return Data([(major << 5) | 24, UInt8(count)]) }
        return Data([(major << 5) | 25, UInt8(count >> 8), UInt8(count & 255)])
    }
}
