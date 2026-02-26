import Foundation
import Combine
import SwiftUI

// MARK: - OnboardingViewModel
// Manages the first-launch onboarding flow: API key setup, Google auth,
// sender configuration, and initial industry/region selection.

@MainActor
class OnboardingViewModel: ObservableObject {

  // MARK: - State
  @Published var currentStep: OnboardingStep = .welcome
  @Published var isCompleted: Bool = false
  @Published var isValidating: Bool = false
  @Published var validationError: String?

  // MARK: - User Input
  @Published var perplexityAPIKey: String = ""
  @Published var senderName: String = ""
  @Published var senderEmail: String = ""
  @Published var selectedIndustry: String = ""
  @Published var selectedRegion: String = ""
  @Published var googleConnected: Bool = false

  // MARK: - Progress
  var progress: Double {
    let total = Double(OnboardingStep.allCases.count)
    let current = Double(OnboardingStep.allCases.firstIndex(of: currentStep) ?? 0)
    return current / total
  }

  var canProceed: Bool {
    switch currentStep {
    case .welcome:
      return true
    case .apiKey:
      return !perplexityAPIKey.isEmpty && perplexityAPIKey.count > 10
    case .senderInfo:
      return !senderName.isEmpty && !senderEmail.isEmpty && senderEmail.contains("@")
    case .googleAuth:
      return true // Optional step
    case .industrySelection:
      return !selectedIndustry.isEmpty && !selectedRegion.isEmpty
    case .complete:
      return true
    }
  }

  // MARK: - Navigation

  func nextStep() {
    guard canProceed else { return }
    guard let currentIndex = OnboardingStep.allCases.firstIndex(of: currentStep),
          currentIndex + 1 < OnboardingStep.allCases.count else {
      completeOnboarding()
      return
    }
    currentStep = OnboardingStep.allCases[currentIndex + 1]
  }

  func previousStep() {
    guard let currentIndex = OnboardingStep.allCases.firstIndex(of: currentStep),
          currentIndex > 0 else { return }
    currentStep = OnboardingStep.allCases[currentIndex - 1]
  }

  func skipStep() {
    nextStep()
  }

  // MARK: - Validation

  func validateAPIKey() async {
    isValidating = true
    validationError = nil

    // Quick format check
    let key = perplexityAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      validationError = "API key cannot be empty."
      isValidating = false
      return
    }

    guard key.hasPrefix("pplx-") else {
      validationError = "Perplexity API keys should start with 'pplx-'."
      isValidating = false
      return
    }

    // Real validation via a test API call
    do {
      let url = URL(string: "https://api.perplexity.ai/chat/completions")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let body: [String: Any] = [
        "model": "sonar",
        "messages": [["role": "user", "content": "test"]],
        "max_tokens": 5
      ]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.timeoutInterval = 15

      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse {
        if http.statusCode == 200 {
          validationError = nil
        } else if http.statusCode == 401 {
          validationError = "Invalid API key. Please check your Perplexity dashboard."
        } else {
          validationError = "API returned status \(http.statusCode). Key may still be valid."
        }
      }
    } catch {
      validationError = "Could not validate key: \(error.localizedDescription)"
    }

    isValidating = false
  }

  // MARK: - Completion

  func completeOnboarding() {
    // Save all onboarding data to DataStore/Settings
    var settings = DataStore.shared.settings
    settings.perplexityAPIKey = perplexityAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.senderName = senderName
    settings.senderEmail = senderEmail
    settings.defaultIndustry = selectedIndustry
    settings.defaultRegion = selectedRegion
    DataStore.shared.settings = settings
    DataStore.shared.saveSettings()

    // Mark onboarding as completed
    UserDefaults.standard.set(true, forKey: "onboardingCompleted")
    isCompleted = true
  }

  // MARK: - Check

  static var needsOnboarding: Bool {
    !UserDefaults.standard.bool(forKey: "onboardingCompleted")
  }

  static func resetOnboarding() {
    UserDefaults.standard.removeObject(forKey: "onboardingCompleted")
  }
}

// MARK: - Onboarding Steps

enum OnboardingStep: String, CaseIterable {
  case welcome = "Welcome"
  case apiKey = "API Key"
  case senderInfo = "Sender Info"
  case googleAuth = "Google Auth"
  case industrySelection = "Industry"
  case complete = "Complete"

  var title: String {
    switch self {
    case .welcome: return "Welcome to HarpoOutreach"
    case .apiKey: return "Perplexity API Key"
    case .senderInfo: return "Your Information"
    case .googleAuth: return "Connect Google"
    case .industrySelection: return "Target Market"
    case .complete: return "You're All Set!"
    }
  }

  var subtitle: String {
    switch self {
    case .welcome: return "AI-powered B2B outreach for compliance professionals."
    case .apiKey: return "Enter your Perplexity API key to enable AI research."
    case .senderInfo: return "Configure your sender identity for outreach emails."
    case .googleAuth: return "Connect Gmail and Sheets for seamless integration."
    case .industrySelection: return "Select your default target industry and region."
    case .complete: return "Your workspace is ready. Start prospecting!"
    }
  }

  var isOptional: Bool {
    self == .googleAuth
  }
}
