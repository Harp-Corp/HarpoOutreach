//
//  PersonalizationEngine.swift
//  HarpoOutreach
//
//  AI-powered email personalization based on company/lead context
//

import Foundation

// MARK: - Personalization Context

struct PersonalizationContext {
  let leadName: String
  let leadTitle: String
  let company: String
  let industry: String
  let companySize: String
  let website: String
  let researchSummary: String
  let previousInteractions: Int
  let language: String
  
  init(
    leadName: String = "",
    leadTitle: String = "",
    company: String = "",
    industry: String = "",
    companySize: String = "",
    website: String = "",
    researchSummary: String = "",
    previousInteractions: Int = 0,
    language: String = "de"
  ) {
    self.leadName = leadName
    self.leadTitle = leadTitle
    self.company = company
    self.industry = industry
    self.companySize = companySize
    self.website = website
    self.researchSummary = researchSummary
    self.previousInteractions = previousInteractions
    self.language = language
  }
}

// MARK: - Personalization Result

struct PersonalizedEmail {
  let subject: String
  let body: String
  let openingLine: String
  let closingLine: String
  let callToAction: String
  let personalizedHook: String
  let confidenceScore: Double // 0-1
}

// MARK: - Tone

enum EmailTone: String, CaseIterable {
  case professional = "Professional"
  case friendly = "Friendly"
  case direct = "Direct"
  case consultative = "Consultative"
  
  var promptModifier: String {
    switch self {
    case .professional: return "formal and professional"
    case .friendly: return "warm and approachable"
    case .direct: return "concise and action-oriented"
    case .consultative: return "advisory and solution-focused"
    }
  }
}

// MARK: - Engine

class PersonalizationEngine {
  
  static let shared = PersonalizationEngine()
  
  // MARK: - Build Personalization Prompt
  
  func buildPersonalizationPrompt(
    context: PersonalizationContext,
    tone: EmailTone = .professional,
    product: String = "Compliance-Automatisierung"
  ) -> String {
    var prompt = "Erstelle eine personalisierte B2B-Outreach-Email.\n\n"
    prompt += "KONTEXT:\n"
    prompt += "- Empfaenger: \(context.leadName)"
    if !context.leadTitle.isEmpty { prompt += " (\(context.leadTitle))" }
    prompt += "\n"
    prompt += "- Unternehmen: \(context.company)\n"
    if !context.industry.isEmpty { prompt += "- Branche: \(context.industry)\n" }
    if !context.companySize.isEmpty { prompt += "- Unternehmensgroesse: \(context.companySize)\n" }
    
    if !context.researchSummary.isEmpty {
      prompt += "\nRECHERCHE ZUM UNTERNEHMEN:\n\(context.researchSummary)\n"
    }
    
    prompt += "\nPRODUKT: \(product)\n"
    prompt += "TON: \(tone.promptModifier)\n"
    prompt += "SPRACHE: \(context.language == "de" ? "Deutsch" : "English")\n"
    
    if context.previousInteractions > 0 {
      prompt += "\nHINWEIS: Dies ist Follow-Up Nr. \(context.previousInteractions + 1). "
      prompt += "Beziehe dich auf vorherige Kontaktaufnahme.\n"
    }
    
    prompt += "\nANFORDERUNGEN:\n"
    prompt += "1. Subject-Line die spezifisch auf das Unternehmen eingeht\n"
    prompt += "2. Eroeffnung die zeigt dass du das Unternehmen recherchiert hast\n"
    prompt += "3. Klarer Value-Proposition bezogen auf deren Branche\n"
    prompt += "4. Konkreter Call-to-Action\n"
    prompt += "5. Maximal 150 Woerter\n"
    
    return prompt
  }
  
  // MARK: - Extract Personalization Hooks
  
  func extractHooks(from research: String, company: String) -> [String] {
    var hooks: [String] = []
    
    let regulatoryKeywords = [
      "DORA", "NIS2", "GDPR", "DSGVO", "MaRisk", "BAIT",
      "BaFin", "ISO 27001", "SOC 2", "PCI DSS", "AI Act"
    ]
    
    for keyword in regulatoryKeywords {
      if research.localizedCaseInsensitiveContains(keyword) {
        hooks.append("Regulatorischer Bezug: \(keyword)")
      }
    }
    
    let growthIndicators = [
      "expansion", "wachstum", "growth", "funding",
      "acquisition", "uebernahme", "new office", "hiring"
    ]
    
    for indicator in growthIndicators {
      if research.localizedCaseInsensitiveContains(indicator) {
        hooks.append("Wachstumssignal: \(indicator)")
      }
    }
    
    let painPoints = [
      "legacy", "manual", "compliance", "audit",
      "risk", "security breach", "fine", "penalty"
    ]
    
    for pain in painPoints {
      if research.localizedCaseInsensitiveContains(pain) {
        hooks.append("Pain Point: \(pain)")
      }
    }
    
    return hooks
  }
  
  // MARK: - Generate Subject Variants
  
  func generateSubjectVariants(
    context: PersonalizationContext,
    hooks: [String]
  ) -> [String] {
    var subjects: [String] = []
    
    // Variant 1: Company-specific
    subjects.append("\(context.company) - Compliance-Automatisierung fuer \(context.industry)")
    
    // Variant 2: Pain-point based
    if let firstHook = hooks.first(where: { $0.contains("Pain Point") }) {
      let pain = firstHook.replacingOccurrences(of: "Pain Point: ", with: "")
      subjects.append("\(pain.capitalized)-Herausforderung bei \(context.company) loesen")
    }
    
    // Variant 3: Regulatory urgency
    if let regHook = hooks.first(where: { $0.contains("Regulatorisch") }) {
      let reg = regHook.replacingOccurrences(of: "Regulatorischer Bezug: ", with: "")
      subjects.append("\(reg)-Compliance: Automatisierte Loesung fuer \(context.company)")
    }
    
    // Variant 4: Question-based
    subjects.append("Wie \(context.company) Compliance-Prozesse um 70% beschleunigen kann")
    
    // Fallback if no hooks
    if subjects.count < 2 {
      subjects.append("Partnerschaft: \(context.company) x Harpocrates")
    }
    
    return subjects
  }
  
  // MARK: - Score Personalization Quality
  
  func scorePersonalization(email: String, context: PersonalizationContext) -> Double {
    var score = 0.0
    let maxScore = 5.0
    
    // Check company name mention
    if email.contains(context.company) { score += 1.0 }
    
    // Check lead name mention
    if email.contains(context.leadName) { score += 1.0 }
    
    // Check industry reference
    if !context.industry.isEmpty && email.localizedCaseInsensitiveContains(context.industry) {
      score += 1.0
    }
    
    // Check for specific data points (numbers, percentages)
    let numberPattern = try? NSRegularExpression(pattern: "\\d+[%\\.]?")
    let numberMatches = numberPattern?.numberOfMatches(
      in: email, range: NSRange(email.startIndex..., in: email)
    ) ?? 0
    if numberMatches > 0 { score += 0.5 }
    
    // Check email length (ideal: 80-200 words)
    let wordCount = email.split(separator: " ").count
    if wordCount >= 80 && wordCount <= 200 { score += 0.5 }
    
    return min(score / maxScore, 1.0)
  }
  
  // MARK: - Build Follow-Up Context
  
  func buildFollowUpPrompt(
    context: PersonalizationContext,
    previousEmail: String,
    daysSinceLastContact: Int
  ) -> String {
    var prompt = "Erstelle ein Follow-Up zu einer vorherigen Email.\n\n"
    prompt += "VORHERIGE EMAIL (vor \(daysSinceLastContact) Tagen gesendet):\n"
    prompt += previousEmail.prefix(500) + "\n\n"
    prompt += "EMPFAENGER: \(context.leadName) bei \(context.company)\n"
    prompt += "BRANCHE: \(context.industry)\n\n"
    prompt += "ANFORDERUNGEN:\n"
    prompt += "1. Kurz und freundlich (max 80 Woerter)\n"
    prompt += "2. Neuer Mehrwert oder Insight anbieten\n"
    prompt += "3. Nicht aufdringlich\n"
    prompt += "4. Konkreter naechster Schritt vorschlagen\n"
    return prompt
  }
  
  // MARK: - Detect Language
  
  func detectLanguage(for context: PersonalizationContext) -> String {
    let germanDomains = [".de", ".at", ".ch"]
    let domain = context.website.lowercased()
    
    for tld in germanDomains {
      if domain.hasSuffix(tld) { return "de" }
    }
    
    let germanIndicators = [
      "GmbH", "AG", "e.V.", "KG", "OHG",
      "Deutschland", "Oesterreich", "Schweiz"
    ]
    
    let combined = context.company + " " + context.industry
    for indicator in germanIndicators {
      if combined.contains(indicator) { return "de" }
    }
    
    return "en"
  }
}
