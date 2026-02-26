import Foundation

// MARK: - ResponseParser
// Centralized JSON parsing and content cleaning for all API responses.
// Extracted from PerplexityService to enable reuse across services.

struct ResponseParser {

  // MARK: - JSON Cleaning

  /// Strips markdown fences and extracts valid JSON from raw API output.
  static func cleanJSON(_ content: String) -> String {
    var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
    else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
    if s.hasSuffix("```") { s = String(s.dropLast(3)) }
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("[") || s.hasPrefix("{") { return s }
    if let a = s.firstIndex(of: "["), let b = s.lastIndex(of: "]") { return String(s[a...b]) }
    if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { return String(s[a...b]) }
    return s
  }

  // MARK: - JSON Array Parsing

  /// Parses raw API content into an array of string dictionaries.
  /// Handles nested types by converting all values to String.
  static func parseJSONArray(_ content: String) -> [[String: String]] {
    let cleaned = cleanJSON(content)
    guard let data = cleaned.data(using: .utf8) else { return [] }
    do {
      if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        return array.map { dict in
          var result: [String: String] = [:]
          for (key, value) in dict { result[key] = "\(value)" }
          return result
        }
      }
    } catch {}
    return []
  }

  // MARK: - JSON Object Parsing

  /// Parses raw API content into a single dictionary.
  static func parseJSONObject(_ content: String) -> [String: Any]? {
    let cleaned = cleanJSON(content)
    guard let data = cleaned.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  // MARK: - Decodable Parsing

  /// Parses raw API content into a Decodable type.
  static func decode<T: Decodable>(_ type: T.Type, from content: String) -> T? {
    let cleaned = cleanJSON(content)
    guard let data = cleaned.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  // MARK: - Citation Stripping

  /// Removes inline citation markers like [1], [2,3] from text.
  static func stripCitations(_ text: String) -> String {
    var result = text
    let pattern = "\\s*\\[\\d+(,\\s*\\d+)*\\]"
    if let regex = try? NSRegularExpression(pattern: pattern) {
      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Footer Management

  static let companyFooter = "\n\n\u{1F517} www.harpocrates-corp.com | \u{1F4E7} info@harpocrates-corp.com"

  /// Ensures company footer is always at the end of content.
  /// Removes any existing footer before appending a fresh one.
  static func ensureFooter(_ content: String) -> String {
    var clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = clean.range(of: "\u{1F517} www.harpocrates-corp.com") {
      clean = String(clean[clean.startIndex..<range.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let range = clean.range(of: " www.harpocrates-corp.com") {
      clean = String(clean[clean.startIndex..<range.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return clean + companyFooter
  }

  // MARK: - Hashtag Handling

  /// Removes trailing hashtag lines from social post content.
  static func stripTrailingHashtags(_ content: String) -> String {
    let lines = content.components(separatedBy: "\n")
    var result: [String] = []
    var foundNonHashtag = false
    for line in lines.reversed() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty && !foundNonHashtag { continue }
      if trimmed.hasPrefix("#") && !foundNonHashtag { continue }
      foundNonHashtag = true
      result.insert(line, at: 0)
    }
    return result.joined(separator: "\n")
  }

  // MARK: - Name Normalization

  /// Normalizes a name for deduplication by removing titles and extra whitespace.
  static func normalizeName(_ name: String) -> String {
    return name.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "dr. ", with: "")
      .replacingOccurrences(of: "dr ", with: "")
      .replacingOccurrences(of: "prof. ", with: "")
      .replacingOccurrences(of: "prof ", with: "")
      .components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  // MARK: - Email Cleaning

  /// Validates and cleans an email address. Returns empty string if invalid.
  static func cleanEmail(_ email: String) -> String {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("@") && trimmed.contains(".") {
      return trimmed.lowercased()
    }
    return ""
  }

  // MARK: - Employee Count Parsing

  /// Parses employee count from various string formats (e.g. "2,500", "2.500").
  static func parseEmployeeCount(_ value: String?) -> Int {
    guard let value = value else { return 0 }
    if let intVal = Int(value) { return intVal }
    let cleaned = value
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: ".", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(cleaned) ?? 0
  }

  // MARK: - Safe String Extraction

  /// Safely extracts a string value from a dictionary with a fallback default.
  static func string(from dict: [String: Any], key: String, default fallback: String = "") -> String {
    return dict[key] as? String ?? fallback
  }

  /// Safely extracts a boolean value from a dictionary.
  static func bool(from dict: [String: Any], key: String, default fallback: Bool = false) -> Bool {
    return dict[key] as? Bool ?? fallback
  }

  /// Safely extracts a string array from a dictionary.
  static func stringArray(from dict: [String: Any], key: String) -> [String] {
    return dict[key] as? [String] ?? []
  }
}
