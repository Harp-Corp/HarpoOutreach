import Foundation
import SQLite3

// MARK: - DatabaseService
// SQLite-basierte Persistenz fuer HarpoOutreach.
// Ersetzt die bisherige JSON-Datei-Speicherung.
// Verwendet die SQLite3 C-API direkt (kein externes Framework noetig auf macOS).

final class DatabaseService {

    // MARK: - Singleton
    static let shared = DatabaseService()

    // MARK: - Private Properties
    private var db: OpaquePointer?
    /// Serial queue fuer thread-sichere Datenbankzugriffe
    private let queue = DispatchQueue(label: "com.harpocrates.DatabaseService", qos: .userInitiated)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        openDatabase()
        createTables()
    }

    // MARK: - Database Location

    /// Oeffnet (oder erstellt) die SQLite-Datenbank in Application Support/HarpoOutreach/
    private func openDatabase() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let dbURL = appDir.appendingPathComponent("harpo.db")
        let dbPath = dbURL.path

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("[DB] Opened database at \(dbPath)")
            // WAL-Modus fuer bessere Concurrent-Performance
            executeSQL("PRAGMA journal_mode = WAL;")
            executeSQL("PRAGMA foreign_keys = ON;")
        } else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DB] ERROR opening database: \(errMsg)")
        }
    }

    // MARK: - Schema Creation

    /// Erstellt alle notwendigen Tabellen falls nicht vorhanden (idempotent)
    private func createTables() {
        // --- companies ---
        executeSQL("""
            CREATE TABLE IF NOT EXISTS companies (
                id              TEXT PRIMARY KEY NOT NULL,
                name            TEXT NOT NULL DEFAULT '',
                industry        TEXT NOT NULL DEFAULT '',
                region          TEXT NOT NULL DEFAULT '',
                website         TEXT NOT NULL DEFAULT '',
                linkedin_url    TEXT NOT NULL DEFAULT '',
                description     TEXT NOT NULL DEFAULT '',
                size            TEXT NOT NULL DEFAULT '',
                country         TEXT NOT NULL DEFAULT '',
                nace_code       TEXT NOT NULL DEFAULT '',
                employee_count  INTEGER NOT NULL DEFAULT 0,
                updated_at      REAL NOT NULL DEFAULT 0
            );
        """)

        // --- leads ---
        executeSQL("""
            CREATE TABLE IF NOT EXISTS leads (
                id                      TEXT PRIMARY KEY NOT NULL,
                name                    TEXT NOT NULL DEFAULT '',
                title                   TEXT NOT NULL DEFAULT '',
                company                 TEXT NOT NULL DEFAULT '',
                email                   TEXT NOT NULL DEFAULT '',
                email_verified          INTEGER NOT NULL DEFAULT 0,
                linkedin_url            TEXT NOT NULL DEFAULT '',
                phone                   TEXT NOT NULL DEFAULT '',
                responsibility          TEXT NOT NULL DEFAULT '',
                status                  TEXT NOT NULL DEFAULT 'Identified',
                source                  TEXT NOT NULL DEFAULT '',
                verification_notes      TEXT NOT NULL DEFAULT '',
                drafted_email_json      TEXT,
                follow_up_email_json    TEXT,
                date_identified         REAL NOT NULL DEFAULT 0,
                date_email_sent         REAL,
                date_follow_up_sent     REAL,
                reply_received          TEXT NOT NULL DEFAULT '',
                is_manually_created     INTEGER NOT NULL DEFAULT 0,
                scheduled_send_date     REAL,
                opted_out               INTEGER NOT NULL DEFAULT 0,
                opt_out_date            REAL,
                delivery_status         TEXT NOT NULL DEFAULT 'Pending',
                updated_at              REAL NOT NULL DEFAULT 0
            );
        """)

        // --- social_posts ---
        executeSQL("""
            CREATE TABLE IF NOT EXISTS social_posts (
                id              TEXT PRIMARY KEY NOT NULL,
                platform        TEXT NOT NULL DEFAULT 'LinkedIn',
                content         TEXT NOT NULL DEFAULT '',
                hashtags_json   TEXT NOT NULL DEFAULT '[]',
                created_date    REAL NOT NULL DEFAULT 0,
                is_published    INTEGER NOT NULL DEFAULT 0,
                updated_at      REAL NOT NULL DEFAULT 0
            );
        """)

        // --- blocklist (Opt-Out-Liste) ---
        executeSQL("""
            CREATE TABLE IF NOT EXISTS blocklist (
                email       TEXT PRIMARY KEY NOT NULL COLLATE NOCASE,
                reason      TEXT NOT NULL DEFAULT '',
                opted_out_at REAL NOT NULL DEFAULT 0
            );
        """)

        // --- settings (Key-Value Store) ---
        executeSQL("""
            CREATE TABLE IF NOT EXISTS settings (
                key         TEXT PRIMARY KEY NOT NULL,
                value_json  TEXT NOT NULL DEFAULT 'null'
            );
        """)

        // Indizes fuer haeufige Abfragen
        executeSQL("CREATE INDEX IF NOT EXISTS idx_leads_email   ON leads(email);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_leads_company ON leads(company);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_leads_status  ON leads(status);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_companies_name ON companies(name);")

        print("[DB] Tables created / verified")
    }

    // MARK: - Low-Level Helpers

    /// Fuehrt ein SQL-Statement ohne Rueckgabe aus (CREATE, DROP, PRAGMA, ...)
    @discardableResult
    private func executeSQL(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[DB] SQL error (\(rc)): \(msg)\n  SQL: \(sql.prefix(120))")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    /// Bereitet ein SQL-Statement vor
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DB] prepare error: \(errMsg)\n  SQL: \(sql.prefix(120))")
            return nil
        }
        return stmt
    }

    // MARK: - Date Helpers (speichern als Unix-Timestamp)

    private func dateToDouble(_ date: Date?) -> Double? {
        guard let date = date else { return nil }
        return date.timeIntervalSince1970
    }

    private func doubleToDate(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    // MARK: - JSON Helpers

    private func encodeToJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value = value else { return nil }
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private func decodeFromJSON<T: Decodable>(_ json: String?, as type: T.Type) -> T? {
        guard let json = json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let value = try? decoder.decode(T.self, from: data) else {
            return nil
        }
        return value
    }

    // MARK: - Column Helpers

    private func columnString(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }

    private func columnOptionalString(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cStr)
    }

    private func columnDouble(_ stmt: OpaquePointer, _ col: Int32) -> Double {
        return sqlite3_column_double(stmt, col)
    }

    private func columnOptionalDouble(_ stmt: OpaquePointer, _ col: Int32) -> Double? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, col)
    }

    private func columnInt(_ stmt: OpaquePointer, _ col: Int32) -> Int {
        return Int(sqlite3_column_int(stmt, col))
    }

    private func columnBool(_ stmt: OpaquePointer, _ col: Int32) -> Bool {
        return sqlite3_column_int(stmt, col) != 0
    }

    // MARK: - Bind Helpers

    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, nil)
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func bindDouble(_ stmt: OpaquePointer, _ idx: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, idx, value)
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, _ idx: Int32, _ value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, idx, v)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func bindInt(_ stmt: OpaquePointer, _ idx: Int32, _ value: Int) {
        sqlite3_bind_int(stmt, idx, Int32(value))
    }

    private func bindBool(_ stmt: OpaquePointer, _ idx: Int32, _ value: Bool) {
        sqlite3_bind_int(stmt, idx, value ? 1 : 0)
    }

    // MARK: - Companies CRUD

    func saveCompany(_ company: Company) {
        queue.sync { self._saveCompany(company) }
    }

    func saveCompanies(_ companies: [Company]) {
        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")
            for company in companies { self._saveCompany(company) }
            self.executeSQL("COMMIT;")
        }
    }

    func loadCompanies() -> [Company] {
        return queue.sync { self._loadCompanies() }
    }

    func deleteCompany(_ id: UUID) {
        queue.sync {
            guard let stmt = self.prepare("DELETE FROM companies WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] deleteCompany error: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }

    private func _saveCompany(_ company: Company) {
        let sql = """
            INSERT OR REPLACE INTO companies
                (id, name, industry, region, website, linkedin_url,
                 description, size, country, nace_code, employee_count, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, company.id.uuidString)
        bindText(stmt, 2, company.name)
        bindText(stmt, 3, company.industry)
        bindText(stmt, 4, company.region)
        bindText(stmt, 5, company.website)
        bindText(stmt, 6, company.linkedInURL)
        bindText(stmt, 7, company.description)
        bindText(stmt, 8, company.size)
        bindText(stmt, 9, company.country)
        bindText(stmt, 10, company.naceCode)
        bindInt(stmt, 11, company.employeeCount)
        bindDouble(stmt, 12, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[DB] saveCompany error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func _loadCompanies() -> [Company] {
        guard let stmt = prepare("SELECT id, name, industry, region, website, linkedin_url, description, size, country, nace_code, employee_count FROM companies ORDER BY name ASC;") else { return [] }
        defer { sqlite3_finalize(stmt) }

        var companies: [Company] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = columnString(stmt, 0)
            guard let id = UUID(uuidString: idStr) else { continue }
            let company = Company(
                id: id,
                name: columnString(stmt, 1),
                industry: columnString(stmt, 2),
                region: columnString(stmt, 3),
                website: columnString(stmt, 4),
                linkedInURL: columnString(stmt, 5),
                description: columnString(stmt, 6),
                size: columnString(stmt, 7),
                country: columnString(stmt, 8),
                naceCode: columnString(stmt, 9),
                employeeCount: columnInt(stmt, 10)
            )
            companies.append(company)
        }
        return companies
    }

    // MARK: - Leads CRUD

    func saveLead(_ lead: Lead) {
        queue.sync { self._saveLead(lead) }
    }

    func saveLeads(_ leads: [Lead]) {
        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")
            for lead in leads { self._saveLead(lead) }
            self.executeSQL("COMMIT;")
        }
    }

    func loadLeads() -> [Lead] {
        return queue.sync { self._loadLeads() }
    }

    func deleteLead(_ id: UUID) {
        queue.sync {
            guard let stmt = self.prepare("DELETE FROM leads WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] deleteLead error: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }

    private func _saveLead(_ lead: Lead) {
        let sql = """
            INSERT OR REPLACE INTO leads
                (id, name, title, company, email, email_verified,
                 linkedin_url, phone, responsibility, status, source,
                 verification_notes, drafted_email_json, follow_up_email_json,
                 date_identified, date_email_sent, date_follow_up_sent,
                 reply_received, is_manually_created,
                 scheduled_send_date, opted_out, opt_out_date,
                 delivery_status, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, lead.id.uuidString)
        bindText(stmt, 2, lead.name)
        bindText(stmt, 3, lead.title)
        bindText(stmt, 4, lead.company)
        bindText(stmt, 5, lead.email)
        bindBool(stmt, 6, lead.emailVerified)
        bindText(stmt, 7, lead.linkedInURL)
        bindText(stmt, 8, lead.phone)
        bindText(stmt, 9, lead.responsibility)
        bindText(stmt, 10, lead.status.rawValue)
        bindText(stmt, 11, lead.source)
        bindText(stmt, 12, lead.verificationNotes)
        bindOptionalText(stmt, 13, encodeToJSON(lead.draftedEmail))
        bindOptionalText(stmt, 14, encodeToJSON(lead.followUpEmail))
        bindDouble(stmt, 15, lead.dateIdentified.timeIntervalSince1970)
        bindOptionalDouble(stmt, 16, dateToDouble(lead.dateEmailSent))
        bindOptionalDouble(stmt, 17, dateToDouble(lead.dateFollowUpSent))
        bindText(stmt, 18, lead.replyReceived)
        bindBool(stmt, 19, lead.isManuallyCreated)
        bindOptionalDouble(stmt, 20, dateToDouble(lead.scheduledSendDate))
        bindBool(stmt, 21, lead.optedOut)
        bindOptionalDouble(stmt, 22, dateToDouble(lead.optOutDate))
        bindText(stmt, 23, lead.deliveryStatus.rawValue)
        bindDouble(stmt, 24, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[DB] saveLead error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func _loadLeads() -> [Lead] {
        let sql = """
            SELECT id, name, title, company, email, email_verified,
                   linkedin_url, phone, responsibility, status, source,
                   verification_notes, drafted_email_json, follow_up_email_json,
                   date_identified, date_email_sent, date_follow_up_sent,
                   reply_received, is_manually_created,
                   scheduled_send_date, opted_out, opt_out_date,
                   delivery_status
            FROM leads ORDER BY date_identified DESC;
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var leads: [Lead] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = columnString(stmt, 0)
            guard let id = UUID(uuidString: idStr) else { continue }

            let statusRaw = columnString(stmt, 9)
            let status = LeadStatus(rawValue: statusRaw) ?? .identified

            let deliveryRaw = columnString(stmt, 22)
            let deliveryStatus = DeliveryStatus(rawValue: deliveryRaw) ?? .pending

            let draftedEmail: OutboundEmail? = decodeFromJSON(
                columnOptionalString(stmt, 12), as: OutboundEmail.self
            )
            let followUpEmail: OutboundEmail? = decodeFromJSON(
                columnOptionalString(stmt, 13), as: OutboundEmail.self
            )

            let dateIdentifiedTS = columnDouble(stmt, 14)
            let dateIdentified = dateIdentifiedTS > 0
                ? Date(timeIntervalSince1970: dateIdentifiedTS)
                : Date()

            let dateEmailSent: Date? = columnOptionalDouble(stmt, 15)
                .flatMap { doubleToDate($0) }
            let dateFollowUpSent: Date? = columnOptionalDouble(stmt, 16)
                .flatMap { doubleToDate($0) }
            let scheduledSendDate: Date? = columnOptionalDouble(stmt, 19)
                .flatMap { doubleToDate($0) }
            let optOutDate: Date? = columnOptionalDouble(stmt, 21)
                .flatMap { doubleToDate($0) }

            let lead = Lead(
                id: id,
                name: columnString(stmt, 1),
                title: columnString(stmt, 2),
                company: columnString(stmt, 3),
                email: columnString(stmt, 4),
                emailVerified: columnBool(stmt, 5),
                linkedInURL: columnString(stmt, 6),
                phone: columnString(stmt, 7),
                responsibility: columnString(stmt, 8),
                status: status,
                source: columnString(stmt, 10),
                verificationNotes: columnString(stmt, 11),
                draftedEmail: draftedEmail,
                followUpEmail: followUpEmail,
                dateIdentified: dateIdentified,
                dateEmailSent: dateEmailSent,
                dateFollowUpSent: dateFollowUpSent,
                replyReceived: columnString(stmt, 17),
                isManuallyCreated: columnBool(stmt, 18),
                scheduledSendDate: scheduledSendDate,
                optedOut: columnBool(stmt, 20),
                optOutDate: optOutDate,
                deliveryStatus: deliveryStatus
            )
            leads.append(lead)
        }
        return leads
    }

    // MARK: - Social Posts CRUD

    func saveSocialPost(_ post: SocialPost) {
        queue.sync { self._saveSocialPost(post) }
    }

    func saveSocialPosts(_ posts: [SocialPost]) {
        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")
            for post in posts { self._saveSocialPost(post) }
            self.executeSQL("COMMIT;")
        }
    }

    func loadSocialPosts() -> [SocialPost] {
        return queue.sync { self._loadSocialPosts() }
    }

    func deleteSocialPost(_ id: UUID) {
        queue.sync {
            guard let stmt = self.prepare("DELETE FROM social_posts WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] deleteSocialPost error: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }

    private func _saveSocialPost(_ post: SocialPost) {
        let sql = """
            INSERT OR REPLACE INTO social_posts
                (id, platform, content, hashtags_json, created_date, is_published, updated_at)
            VALUES (?,?,?,?,?,?,?);
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        let hashtagsJSON = encodeToJSON(post.hashtags) ?? "[]"

        bindText(stmt, 1, post.id.uuidString)
        bindText(stmt, 2, post.platform.rawValue)
        bindText(stmt, 3, post.content)
        bindText(stmt, 4, hashtagsJSON)
        bindDouble(stmt, 5, post.createdDate.timeIntervalSince1970)
        bindBool(stmt, 6, post.isPublished)
        bindDouble(stmt, 7, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[DB] saveSocialPost error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func _loadSocialPosts() -> [SocialPost] {
        let sql = """
            SELECT id, platform, content, hashtags_json, created_date, is_published
            FROM social_posts ORDER BY created_date DESC;
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var posts: [SocialPost] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = columnString(stmt, 0)
            guard let id = UUID(uuidString: idStr) else { continue }

            let platformRaw = columnString(stmt, 1)
            let platform = SocialPlatform(rawValue: platformRaw) ?? .linkedin
            let content = columnString(stmt, 2)
            let hashtagsJSON = columnString(stmt, 3)
            let hashtags: [String] = decodeFromJSON(hashtagsJSON, as: [String].self) ?? []
            let createdDateTS = columnDouble(stmt, 4)
            let createdDate = createdDateTS > 0
                ? Date(timeIntervalSince1970: createdDateTS)
                : Date()
            let isPublished = columnBool(stmt, 5)

            let post = SocialPost(
                id: id,
                platform: platform,
                content: content,
                hashtags: hashtags,
                createdDate: createdDate,
                isPublished: isPublished
            )
            posts.append(post)
        }
        return posts
    }

    // MARK: - Blocklist (Opt-Out)

    /// Fuegt eine E-Mail-Adresse zur Blockliste hinzu
    func addToBlocklist(email: String, reason: String) {
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO blocklist (email, reason, opted_out_at)
                VALUES (?, ?, ?);
            """
            guard let stmt = self.prepare(sql) else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, email.lowercased().trimmingCharacters(in: .whitespaces))
            self.bindText(stmt, 2, reason)
            self.bindDouble(stmt, 3, Date().timeIntervalSince1970)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] addToBlocklist error: \(String(cString: sqlite3_errmsg(self.db)))")
            } else {
                print("[DB] Blocklist: added \(email)")
            }
        }
    }

    /// Prueft ob eine E-Mail-Adresse blockiert ist
    func isBlocked(email: String) -> Bool {
        return queue.sync {
            let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
            guard let stmt = self.prepare("SELECT COUNT(*) FROM blocklist WHERE email = ?;") else { return false }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, normalized)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) > 0
            }
            return false
        }
    }

    /// Laedt alle Eintraege der Blockliste
    func loadBlocklist() -> [(email: String, reason: String, date: Date)] {
        return queue.sync {
            guard let stmt = self.prepare("SELECT email, reason, opted_out_at FROM blocklist ORDER BY opted_out_at DESC;") else { return [] }
            defer { sqlite3_finalize(stmt) }
            var list: [(email: String, reason: String, date: Date)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let email = self.columnString(stmt, 0)
                let reason = self.columnString(stmt, 1)
                let ts = self.columnDouble(stmt, 2)
                let date = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
                list.append((email: email, reason: reason, date: date))
            }
            return list
        }
    }

    /// Entfernt eine E-Mail-Adresse aus der Blockliste
    func removeFromBlocklist(email: String) {
        queue.sync {
            let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
            guard let stmt = self.prepare("DELETE FROM blocklist WHERE email = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, normalized)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] removeFromBlocklist error: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }

    // MARK: - Duplicate Checks

    /// Prueft ob ein Unternehmen mit diesem Namen bereits existiert
    func companyExists(name: String) -> Bool {
        return queue.sync {
            guard let stmt = self.prepare("SELECT COUNT(*) FROM companies WHERE LOWER(name) = LOWER(?);") else { return false }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, name)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) > 0
            }
            return false
        }
    }

    /// Prueft ob ein Lead mit diesem Namen und Unternehmen bereits existiert
    func leadExists(name: String, company: String) -> Bool {
        return queue.sync {
            guard let stmt = self.prepare("SELECT COUNT(*) FROM leads WHERE LOWER(name) = LOWER(?) AND LOWER(company) = LOWER(?);") else { return false }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, name)
            self.bindText(stmt, 2, company)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) > 0
            }
            return false
        }
    }

    /// Prueft ob eine E-Mail-Adresse bereits einem Lead zugeordnet ist
    func leadExistsByEmail(email: String) -> Bool {
        return queue.sync {
            let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
            guard let stmt = self.prepare("SELECT COUNT(*) FROM leads WHERE LOWER(email) = ?;") else { return false }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, normalized)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) > 0
            }
            return false
        }
    }

    // MARK: - CSV Export

    /// Exportiert alle Leads als CSV-String
    func exportLeadsCSV() -> String {
        let leads = loadLeads()
        var lines: [String] = []
        // Header
        lines.append("id,name,title,company,email,emailVerified,linkedInURL,phone,responsibility,status,source,dateIdentified,dateEmailSent,dateFollowUpSent,replyReceived,scheduledSendDate,optedOut,deliveryStatus")
        // Data rows
        let df = ISO8601DateFormatter()
        for lead in leads {
            let fields: [String] = [
                csvEscape(lead.id.uuidString),
                csvEscape(lead.name),
                csvEscape(lead.title),
                csvEscape(lead.company),
                csvEscape(lead.email),
                lead.emailVerified ? "true" : "false",
                csvEscape(lead.linkedInURL),
                csvEscape(lead.phone),
                csvEscape(lead.responsibility),
                csvEscape(lead.status.rawValue),
                csvEscape(lead.source),
                csvEscape(df.string(from: lead.dateIdentified)),
                lead.dateEmailSent.map { csvEscape(df.string(from: $0)) } ?? "",
                lead.dateFollowUpSent.map { csvEscape(df.string(from: $0)) } ?? "",
                csvEscape(lead.replyReceived),
                lead.scheduledSendDate.map { csvEscape(df.string(from: $0)) } ?? "",
                lead.optedOut ? "true" : "false",
                csvEscape(lead.deliveryStatus.rawValue)
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Exportiert alle Unternehmen als CSV-String
    func exportCompaniesCSV() -> String {
        let companies = loadCompanies()
        var lines: [String] = []
        // Header
        lines.append("id,name,industry,region,website,linkedInURL,description,size,country,naceCode,employeeCount")
        // Data rows
        for company in companies {
            let fields: [String] = [
                csvEscape(company.id.uuidString),
                csvEscape(company.name),
                csvEscape(company.industry),
                csvEscape(company.region),
                csvEscape(company.website),
                csvEscape(company.linkedInURL),
                csvEscape(company.description),
                csvEscape(company.size),
                csvEscape(company.country),
                csvEscape(company.naceCode),
                "\(company.employeeCount)"
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Escaped einen Wert fuer CSV (Anführungszeichen-Escaping nach RFC 4180)
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - CSV Import

    /// Importiert Leads aus einem CSV-String. Erwartet Spalten:
    /// name, title, company, email, linkedInURL, responsibility (Reihenfolge via Header-Zeile)
    /// Gibt die Anzahl der neu importierten Leads zurueck.
    @discardableResult
    func importLeadsFromCSV(_ csvString: String) -> Int {
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else {
            print("[DB] importLeadsFromCSV: not enough rows (need header + data)")
            return 0
        }

        // Header parsen
        let headers = parseCSVRow(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func colIndex(_ name: String) -> Int? { headers.firstIndex(of: name) }

        let nameCol         = colIndex("name")
        let titleCol        = colIndex("title")
        let companyCol      = colIndex("company")
        let emailCol        = colIndex("email")
        let linkedInCol     = colIndex("linkedinurl")
        let responsibilityCol = colIndex("responsibility")

        guard let nameIdx = nameCol, let companyIdx = companyCol else {
            print("[DB] importLeadsFromCSV: missing required columns 'name' and/or 'company'")
            return 0
        }

        var importCount = 0
        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")
            for line in lines.dropFirst() {
                let cols = self.parseCSVRow(line)
                guard cols.count > max(nameIdx, companyIdx) else { continue }

                let name = cols[nameIdx].trimmingCharacters(in: .whitespaces)
                let company = cols[companyIdx].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !company.isEmpty else { continue }

                let email = emailCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? ""

                // Duplikat-Pruefung (inline, da wir schon auf dem queue sind)
                if !email.isEmpty {
                    let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
                    if let stmt = self.prepare("SELECT COUNT(*) FROM leads WHERE LOWER(email) = ?;") {
                        self.bindText(stmt, 1, normalized)
                        if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) > 0 {
                            sqlite3_finalize(stmt)
                            continue // Bereits vorhanden
                        }
                        sqlite3_finalize(stmt)
                    }
                } else {
                    if let stmt = self.prepare("SELECT COUNT(*) FROM leads WHERE LOWER(name) = LOWER(?) AND LOWER(company) = LOWER(?);") {
                        self.bindText(stmt, 1, name)
                        self.bindText(stmt, 2, company)
                        if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) > 0 {
                            sqlite3_finalize(stmt)
                            continue
                        }
                        sqlite3_finalize(stmt)
                    }
                }

                let lead = Lead(
                    name: name,
                    title: titleCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    company: company,
                    email: email,
                    linkedInURL: linkedInCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    responsibility: responsibilityCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    isManuallyCreated: true
                )
                self._saveLead(lead)
                importCount += 1
            }
            self.executeSQL("COMMIT;")
        }
        print("[DB] importLeadsFromCSV: imported \(importCount) leads")
        return importCount
    }

    /// Importiert Unternehmen aus einem CSV-String. Erwartet Spalten:
    /// name, industry, region, website, linkedInURL, description, size, country, naceCode, employeeCount
    @discardableResult
    func importCompaniesFromCSV(_ csvString: String) -> Int {
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else {
            print("[DB] importCompaniesFromCSV: not enough rows (need header + data)")
            return 0
        }

        let headers = parseCSVRow(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func colIndex(_ name: String) -> Int? { headers.firstIndex(of: name) }

        let nameCol        = colIndex("name")
        let industryCol    = colIndex("industry")
        let regionCol      = colIndex("region")
        let websiteCol     = colIndex("website")
        let linkedInCol    = colIndex("linkedinurl")
        let descriptionCol = colIndex("description")
        let sizeCol        = colIndex("size")
        let countryCol     = colIndex("country")
        let naceCodeCol    = colIndex("nacecode")
        let empCountCol    = colIndex("employeecount")

        guard let nameIdx = nameCol else {
            print("[DB] importCompaniesFromCSV: missing required column 'name'")
            return 0
        }

        var importCount = 0
        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")
            for line in lines.dropFirst() {
                let cols = self.parseCSVRow(line)
                guard nameIdx < cols.count else { continue }
                let name = cols[nameIdx].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }

                // Duplikat-Pruefung
                if let stmt = self.prepare("SELECT COUNT(*) FROM companies WHERE LOWER(name) = LOWER(?);") {
                    self.bindText(stmt, 1, name)
                    if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) > 0 {
                        sqlite3_finalize(stmt)
                        continue
                    }
                    sqlite3_finalize(stmt)
                }

                let empCount = empCountCol.flatMap { $0 < cols.count ? Int(cols[$0]) : nil } ?? 0
                let company = Company(
                    name: name,
                    industry: industryCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    region: regionCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    website: websiteCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    linkedInURL: linkedInCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    description: descriptionCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    size: sizeCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    country: countryCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    naceCode: naceCodeCol.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "",
                    employeeCount: empCount
                )
                self._saveCompany(company)
                importCount += 1
            }
            self.executeSQL("COMMIT;")
        }
        print("[DB] importCompaniesFromCSV: imported \(importCount) companies")
        return importCount
    }

    /// Einfacher RFC-4180-kompatibler CSV-Zeilen-Parser
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        // Escaped quote
                        current.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    // MARK: - Migration from JSON

    /// Migriert bestehende JSON-Daten in die SQLite-Datenbank (einmalig beim ersten Start)
    func migrateFromJSON(leads: [Lead], companies: [Company], socialPosts: [SocialPost]) {
        let existingLeads = loadLeads()
        let existingCompanies = loadCompanies()
        let existingSocialPosts = loadSocialPosts()

        var newLeads = 0
        var newCompanies = 0
        var newPosts = 0

        // Bestehende IDs sammeln
        let existingLeadIDs = Set(existingLeads.map { $0.id })
        let existingCompanyIDs = Set(existingCompanies.map { $0.id })
        let existingPostIDs = Set(existingSocialPosts.map { $0.id })

        queue.sync {
            self.executeSQL("BEGIN TRANSACTION;")

            for lead in leads where !existingLeadIDs.contains(lead.id) {
                self._saveLead(lead)
                newLeads += 1
            }
            for company in companies where !existingCompanyIDs.contains(company.id) {
                self._saveCompany(company)
                newCompanies += 1
            }
            for post in socialPosts where !existingPostIDs.contains(post.id) {
                self._saveSocialPost(post)
                newPosts += 1
            }

            self.executeSQL("COMMIT;")
        }

        print("[DB] Migration complete: \(newLeads) leads, \(newCompanies) companies, \(newPosts) posts imported")
    }

    // MARK: - Utility

    /// Gibt die Anzahl aller Leads in der Datenbank zurueck
    func countLeads() -> Int {
        return queue.sync {
            guard let stmt = self.prepare("SELECT COUNT(*) FROM leads;") else { return 0 }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    /// Gibt die Anzahl aller Unternehmen in der Datenbank zurueck
    func countCompanies() -> Int {
        return queue.sync {
            guard let stmt = self.prepare("SELECT COUNT(*) FROM companies;") else { return 0 }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    /// Loesche alle Daten (fuer Tests oder Reset)
    func purgeAll() {
        queue.sync {
            self.executeSQL("DELETE FROM leads;")
            self.executeSQL("DELETE FROM companies;")
            self.executeSQL("DELETE FROM social_posts;")
            self.executeSQL("DELETE FROM blocklist;")
            print("[DB] All data purged")
        }
    }

    /// Laedt Leads die fuer den geplanten Versand faellig sind
    func loadScheduledLeads(before date: Date) -> [Lead] {
        return queue.sync {
            let sql = """
                SELECT id, name, title, company, email, email_verified,
                       linkedin_url, phone, responsibility, status, source,
                       verification_notes, drafted_email_json, follow_up_email_json,
                       date_identified, date_email_sent, date_follow_up_sent,
                       reply_received, is_manually_created,
                       scheduled_send_date, opted_out, opt_out_date,
                       delivery_status
                FROM leads
                WHERE scheduled_send_date IS NOT NULL
                  AND scheduled_send_date <= ?
                  AND date_email_sent IS NULL
                  AND opted_out = 0
                ORDER BY scheduled_send_date ASC;
            """
            guard let stmt = self.prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            self.bindDouble(stmt, 1, date.timeIntervalSince1970)

            var leads: [Lead] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = self.columnString(stmt, 0)
                guard let id = UUID(uuidString: idStr) else { continue }

                let statusRaw = self.columnString(stmt, 9)
                let status = LeadStatus(rawValue: statusRaw) ?? .identified
                let deliveryRaw = self.columnString(stmt, 22)
                let deliveryStatus = DeliveryStatus(rawValue: deliveryRaw) ?? .pending

                let draftedEmail: OutboundEmail? = self.decodeFromJSON(
                    self.columnOptionalString(stmt, 12), as: OutboundEmail.self
                )
                let followUpEmail: OutboundEmail? = self.decodeFromJSON(
                    self.columnOptionalString(stmt, 13), as: OutboundEmail.self
                )

                let dateIdentifiedTS = self.columnDouble(stmt, 14)
                let dateIdentified = dateIdentifiedTS > 0
                    ? Date(timeIntervalSince1970: dateIdentifiedTS)
                    : Date()

                let lead = Lead(
                    id: id,
                    name: self.columnString(stmt, 1),
                    title: self.columnString(stmt, 2),
                    company: self.columnString(stmt, 3),
                    email: self.columnString(stmt, 4),
                    emailVerified: self.columnBool(stmt, 5),
                    linkedInURL: self.columnString(stmt, 6),
                    phone: self.columnString(stmt, 7),
                    responsibility: self.columnString(stmt, 8),
                    status: status,
                    source: self.columnString(stmt, 10),
                    verificationNotes: self.columnString(stmt, 11),
                    draftedEmail: draftedEmail,
                    followUpEmail: followUpEmail,
                    dateIdentified: dateIdentified,
                    dateEmailSent: self.columnOptionalDouble(stmt, 15).flatMap { self.doubleToDate($0) },
                    dateFollowUpSent: self.columnOptionalDouble(stmt, 16).flatMap { self.doubleToDate($0) },
                    replyReceived: self.columnString(stmt, 17),
                    isManuallyCreated: self.columnBool(stmt, 18),
                    scheduledSendDate: self.columnOptionalDouble(stmt, 19).flatMap { self.doubleToDate($0) },
                    optedOut: self.columnBool(stmt, 20),
                    optOutDate: self.columnOptionalDouble(stmt, 21).flatMap { self.doubleToDate($0) },
                    deliveryStatus: deliveryStatus
                )
                leads.append(lead)
            }
            return leads
        }
    }
}
