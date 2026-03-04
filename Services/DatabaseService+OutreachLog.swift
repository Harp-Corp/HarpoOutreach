import Foundation
import SQLite3

// MARK: - Outreach Log Extension
// Erweitert DatabaseService um ein outreach_log fuer Analytics/Berichte
// Feature 5: Wer wurde wann mit was angeschrieben? Rueckmeldungen? Unsubscribes?

struct OutreachLogEntry: Identifiable {
  let id: UUID
  let leadId: UUID
  let leadName: String
  let company: String
  let email: String
  let action: String       // "email_sent", "follow_up_sent", "reply_received", "opted_out"
  let subject: String
  let channel: String      // "email", "linkedin"
  let timestamp: Date
  let details: String      // z.B. Reply-Text oder Opt-Out-Grund
}

extension DatabaseService {

  // MARK: - Create outreach_log Table
  func createOutreachLogTable() {
    let sql = """
    CREATE TABLE IF NOT EXISTS outreach_log (
      id TEXT PRIMARY KEY NOT NULL,
      lead_id TEXT NOT NULL,
      lead_name TEXT NOT NULL DEFAULT '',
      company TEXT NOT NULL DEFAULT '',
      email TEXT NOT NULL DEFAULT '',
      action TEXT NOT NULL DEFAULT '',
      subject TEXT NOT NULL DEFAULT '',
      channel TEXT NOT NULL DEFAULT 'email',
      timestamp REAL NOT NULL DEFAULT 0,
      details TEXT NOT NULL DEFAULT ''
    );
    """
    executeOutreachSQL(sql)
    executeOutreachSQL("CREATE INDEX IF NOT EXISTS idx_outreach_log_lead ON outreach_log(lead_id);")
    executeOutreachSQL("CREATE INDEX IF NOT EXISTS idx_outreach_log_action ON outreach_log(action);")
    executeOutreachSQL("CREATE INDEX IF NOT EXISTS idx_outreach_log_ts ON outreach_log(timestamp);")
  }

  // MARK: - Log an Outreach Action
  func logOutreach(leadId: UUID, action: String, subject: String = "", channel: String = "email", details: String = "") {
    // Resolve lead info
    let leads = loadLeads()
    let lead = leads.first(where: { $0.id == leadId })
    let entry = OutreachLogEntry(
      id: UUID(),
      leadId: leadId,
      leadName: lead?.name ?? "",
      company: lead?.company ?? "",
      email: lead?.email ?? "",
      action: action,
      subject: subject,
      channel: channel,
      timestamp: Date(),
      details: details
    )
    saveOutreachLogEntry(entry)
  }

  // MARK: - Save Entry
  func saveOutreachLogEntry(_ entry: OutreachLogEntry) {
    createOutreachLogTable()
    let sql = """
    INSERT OR REPLACE INTO outreach_log
    (id, lead_id, lead_name, company, email, action, subject, channel, timestamp, details)
    VALUES (?,?,?,?,?,?,?,?,?,?);
    """
    guard let db = getDB() else { return }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      print("[DB] outreach_log prepare error")
      return
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, (entry.id.uuidString as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (entry.leadId.uuidString as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 3, (entry.leadName as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 4, (entry.company as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 5, (entry.email as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 6, (entry.action as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 7, (entry.subject as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 8, (entry.channel as NSString).utf8String, -1, nil)
    sqlite3_bind_double(stmt, 9, entry.timestamp.timeIntervalSince1970)
    sqlite3_bind_text(stmt, 10, (entry.details as NSString).utf8String, -1, nil)

    if sqlite3_step(stmt) != SQLITE_DONE {
      print("[DB] outreach_log save error")
    }
  }

  // MARK: - Load All Entries
  func loadOutreachLog() -> [OutreachLogEntry] {
    createOutreachLogTable()
    let sql = """
    SELECT id, lead_id, lead_name, company, email, action, subject, channel, timestamp, details
    FROM outreach_log ORDER BY timestamp DESC;
    """
    guard let db = getDB() else { return [] }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }

    var entries: [OutreachLogEntry] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
            let id = UUID(uuidString: idStr),
            let leadIdStr = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
            let leadId = UUID(uuidString: leadIdStr) else { continue }

      let colStr: (Int32) -> String = { col in
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
      }
      let ts = sqlite3_column_double(stmt, 8)

      entries.append(OutreachLogEntry(
        id: id,
        leadId: leadId,
        leadName: colStr(2),
        company: colStr(3),
        email: colStr(4),
        action: colStr(5),
        subject: colStr(6),
        channel: colStr(7),
        timestamp: ts > 0 ? Date(timeIntervalSince1970: ts) : Date(),
        details: colStr(9)
      ))
    }
    return entries
  }

  // MARK: - Analytics Queries

  /// Anzahl Emails gesendet
  func countEmailsSent() -> Int {
    createOutreachLogTable()
    guard let db = getDB() else { return 0 }
    var stmt: OpaquePointer?
    let sql = "SELECT COUNT(*) FROM outreach_log WHERE action = 'email_sent';"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
    defer { sqlite3_finalize(stmt) }
    if sqlite3_step(stmt) == SQLITE_ROW {
      return Int(sqlite3_column_int(stmt, 0))
    }
    return 0
  }

  /// Anzahl Replies erhalten
  func countReplies() -> Int {
    createOutreachLogTable()
    guard let db = getDB() else { return 0 }
    var stmt: OpaquePointer?
    let sql = "SELECT COUNT(*) FROM outreach_log WHERE action = 'reply_received';"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
    defer { sqlite3_finalize(stmt) }
    if sqlite3_step(stmt) == SQLITE_ROW {
      return Int(sqlite3_column_int(stmt, 0))
    }
    return 0
  }

  /// Anzahl Opt-Outs (Red Flags)
  func countOptOuts() -> Int {
    createOutreachLogTable()
    guard let db = getDB() else { return 0 }
    var stmt: OpaquePointer?
    let sql = "SELECT COUNT(*) FROM outreach_log WHERE action = 'opted_out';"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
    defer { sqlite3_finalize(stmt) }
    if sqlite3_step(stmt) == SQLITE_ROW {
      return Int(sqlite3_column_int(stmt, 0))
    }
    return 0
  }

  /// DB-Handle exponieren fuer Extension (nutzt den internen db-Pointer)
  func getDB() -> OpaquePointer? {
    // Zugriff auf die private db-Property via Mirror
    let mirror = Mirror(reflecting: self)
    for child in mirror.children {
      if child.label == "db", let dbPtr = child.value as? OpaquePointer? {
        return dbPtr
      }
    }
    return nil
  }

  /// Helper: SQL ausfuehren ohne Rueckgabe
  func executeOutreachSQL(_ sql: String) {
    guard let db = getDB() else { return }
    var errMsg: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
      let msg = errMsg.map { String(cString: $0) } ?? "unknown"
      print("[DB] outreach SQL error: \(msg)")
      sqlite3_free(errMsg)
    }
  }
}
