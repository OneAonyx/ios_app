import Foundation
import HealthKit

/// Phase-0-Test für Apple Health: Berechtigung anfragen und heutige Schritte lesen.
public enum HealthProbe {
    public static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Wirft einen Fehler, wenn die Signatur kein HealthKit-Recht enthält.
    /// Gibt 0 zurück, wenn es keine Daten gibt oder das Lesen abgelehnt wurde
    /// (HealthKit verrät aus Datenschutzgründen nicht, ob Lesen erlaubt ist).
    public static func requestStepsAccessAndReadToday() async throws -> Double {
        let store = HKHealthStore()
        let steps = HKQuantityType(.stepCount)
        try await store.requestAuthorization(toShare: [], read: [steps])

        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: steps, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let statistics = try await descriptor.result(for: store)
            return statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        }
    }
}
