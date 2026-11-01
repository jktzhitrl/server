import Foundation

extension KeyedDecodingContainer {
    /// Liest einen optionalen Wert und fällt bei fehlendem oder ungültigem Eintrag auf
    /// einen Standardwert zurück. Dadurch bleiben ältere und neuere Projektdateien lesbar.
    @inline(__always)
    func value<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}
