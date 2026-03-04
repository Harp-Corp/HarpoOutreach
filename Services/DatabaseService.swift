import Foundation
import SQLite3

// MARK: - DatabaseService
// SQLite-basierte Persistenz fuer HarpoOutreach.
// Ersetzt die bisherige JSON-Datei-Speicherung.
// Verwendet die SQLite3 C-API direkt (kein externes Framework noetig auf macOS).

final class DatabaseService: @unchecked Sendable {

    // MARK: - Singleton
    static let shared = DatabaseService()