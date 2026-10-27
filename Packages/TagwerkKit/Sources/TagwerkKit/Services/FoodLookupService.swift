import Foundation
import SwiftData
import TagwerkCore

/// Fragt Produkte per Barcode bei Open Food Facts ab (kostenlos, ohne Schlüssel).
/// Ergebnisse landen als eigenes Lebensmittel in der Datenbank, die nächste Abfrage
/// desselben Barcodes braucht dann kein Netz mehr.
public enum FoodLookupService {
    public enum LookupError: LocalizedError {
        case invalidBarcode
        case notFound
        case offline
        case server(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidBarcode: "Der Barcode ist ungültig."
            case .notFound: "Dieses Produkt kennt Open Food Facts noch nicht. Du kannst die Zutatenliste fotografieren oder abtippen."
            case .offline: "Keine Verbindung. Versuche es später noch einmal oder prüfe die Zutatenliste per Kamera."
            case let .server(code): "Open Food Facts antwortet gerade nicht (Fehler \(code))."
            }
        }
    }

    /// Fragt Open Food Facts. In UI-Tests wird nichts abgefragt.
    public static func fetch(barcode raw: String, session: URLSession = .shared) async throws -> ScannedProduct {
        let barcode = Barcode.clean(raw)
        guard Barcode.isValid(barcode), let url = OpenFoodFacts.productURL(barcode: barcode) else {
            throw LookupError.invalidBarcode
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LookupError.offline
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw LookupError.notFound
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LookupError.server(http.statusCode)
        }
        do {
            return try OpenFoodFacts.parse(data, barcode: barcode)
        } catch OpenFoodFacts.ParseError.notFound {
            throw LookupError.notFound
        } catch {
            throw LookupError.server(0)
        }
    }

    /// Bekanntes Produkt aus der Datenbank oder neu abfragen und speichern.
    @MainActor
    public static func lookup(barcode raw: String, in context: ModelContext) async throws -> FoodInfo {
        let barcode = Barcode.clean(raw)
        let catalog = NutritionActions.catalog(in: context)
        if let known = catalog.food(barcode: barcode) {
            return known
        }
        let product = try await fetch(barcode: barcode)
        let report = product.ingredients.map { NutritionActions.analyzer.analyze($0) }
        let info = product.foodInfo(report: report, catalog: catalog)
        NutritionActions.saveCustomFood(info, in: context)
        return info
    }
}
