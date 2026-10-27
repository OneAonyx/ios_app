import Foundation

/// Barcodes (EAN-13, EAN-8, UPC-A) prüfen.
public enum Barcode {
    /// Nur Ziffern, Prüfziffer stimmt.
    public static func isValid(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, [8, 12, 13, 14].contains(digits.count) else { return false }
        let body = digits.dropLast()
        var sum = 0
        // Von rechts: abwechselnd ×3 und ×1.
        for (index, digit) in body.reversed().enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        let check = (10 - sum % 10) % 10
        return check == digits.last
    }

    /// Leerzeichen und Bindestriche entfernen.
    public static func clean(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }
}

/// Produkt aus Open Food Facts (kostenlose, offene Datenbank, ohne Schlüssel).
public struct ScannedProduct: Sendable, Hashable {
    public var barcode: String
    public var name: String
    public var brand: String?
    public var ingredients: String?
    public var proteinPer100: Double?
    public var kcalPer100: Double?
    public var quantity: String?

    public init(
        barcode: String, name: String, brand: String? = nil, ingredients: String? = nil,
        proteinPer100: Double? = nil, kcalPer100: Double? = nil, quantity: String? = nil
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.ingredients = ingredients
        self.proteinPer100 = proteinPer100
        self.kcalPer100 = kcalPer100
        self.quantity = quantity
    }

    /// „Marke Produkt“ ohne doppelte Marke.
    public var displayName: String {
        guard let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) else { return name }
        return "\(brand) \(name)"
    }

    /// Als eigenes Lebensmittel speichern. Die Bewertung kommt aus der Zutatenliste.
    public func foodInfo(report: IngredientReport?, catalog: FoodCatalog) -> FoodInfo {
        let guessed = catalog.bestMatch(for: name)
        return FoodInfo(
            id: "barcode-\(barcode)",
            name: displayName,
            category: guessed?.category ?? .other,
            score: report?.worstScore ?? guessed?.score ?? .moderate,
            flags: Array(Set(report?.hits.flatMap(\.rule.flags) ?? [])).sorted { $0.rawValue < $1.rawValue },
            protein: proteinPer100,
            kcal: kcalPer100,
            portion: 100,
            hint: report.map(\.summary),
            isCustom: true,
            barcode: barcode,
            brand: brand,
            ingredients: ingredients
        )
    }
}

public enum OpenFoodFacts {
    /// Open Food Facts bittet um einen eigenen User-Agent.
    public static let userAgent = "Orbit/0.5 (private iOS-App, https://github.com/OneAonyx/ios_app)"

    public static func productURL(barcode: String) -> URL? {
        let fields = "product_name,product_name_de,generic_name_de,brands,ingredients_text_de,ingredients_text,nutriments,quantity"
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")
    }

    public enum ParseError: Error, Equatable {
        case notFound
        case invalid
    }

    /// Antwort von `/api/v2/product/{barcode}.json` auslesen.
    public static func parse(_ data: Data, barcode: String) throws -> ScannedProduct {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalid
        }
        let status = (object["status"] as? Int) ?? (object["status"] as? NSNumber)?.intValue ?? 0
        guard status == 1, let product = object["product"] as? [String: Any] else {
            throw ParseError.notFound
        }
        func text(_ key: String) -> String? {
            guard let value = product[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            if let value = nutriments[key] as? Double { return value }
            if let value = nutriments[key] as? Int { return Double(value) }
            if let value = nutriments[key] as? NSNumber { return value.doubleValue }
            if let value = nutriments[key] as? String { return Double(value.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let name = text("product_name_de") ?? text("product_name") ?? text("generic_name_de") ?? "Produkt \(barcode)"
        let brand = text("brands").map { $0.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? $0 }
        let kcal = number("energy-kcal_100g") ?? number("energy_100g").map { $0 / 4.184 }
        return ScannedProduct(
            barcode: barcode,
            name: name,
            brand: brand,
            ingredients: text("ingredients_text_de") ?? text("ingredients_text"),
            proteinPer100: number("proteins_100g"),
            kcalPer100: kcal.map { $0.rounded() },
            quantity: text("quantity")
        )
    }
}
