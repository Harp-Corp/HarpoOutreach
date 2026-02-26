//
//  ProspectingViewModel.swift
//  HarpoOutreach
//
//  Extracted from AppViewModel: Company search, contact finding, filtering
//

import Foundation
import Combine

@MainActor
class ProspectingViewModel: ObservableObject {
  
  // MARK: - Published State
  
  @Published var companies: [Company] = []
  @Published var selectedCompany: Company?
  @Published var searchQuery: String = ""
  @Published var searchRegion: String = "Deutschland"
  @Published var searchIndustry: String = ""
  @Published var isSearching: Bool = false
  @Published var searchError: String?
  @Published var companyFilter: CompanyFilter = CompanyFilter()
  
  // MARK: - Dependencies
  
  private let dataStore = DataStore.shared
  private let leadScoring = LeadScoringService.shared
  private let settings = AppSettings.shared
  
  // MARK: - Company Search
  
  func findCompanies(industry: String, region: String) async {
    isSearching = true
    searchError = nil
    
    do {
      let results = try await PerplexityService.findCompanies(
        industry: industry,
        region: region
      )
      
      // Deduplicate against existing leads
      let existingCompanies = dataStore.leads.map {
        (name: $0.company, domain: $0.website ?? "")
      }
      
      var filtered: [Company] = []
      for company in results {
        let dupCheck = leadScoring.checkDuplicate(
          companyName: company.name,
          domain: company.website ?? "",
          existingCompanies: existingCompanies
        )
        if !dupCheck.isDuplicate {
          filtered.append(company)
        }
      }
      
      companies = filtered
      isSearching = false
    } catch {
      searchError = error.localizedDescription
      isSearching = false
    }
  }
  
  // MARK: - Contact Finding
  
  func findContacts(for company: Company) async -> [Contact] {
    do {
      let contacts = try await PerplexityService.findContacts(
        company: company.name,
        website: company.website ?? ""
      )
      return contacts
    } catch {
      searchError = error.localizedDescription
      return []
    }
  }
  
  // MARK: - Company Research
  
  func researchCompany(_ company: Company) async -> String {
    do {
      let result = try await CacheService.shared.getOrFetchResearch(
        forCompany: company.name
      ) { companyName in
        try await PerplexityService.researchChallenges(
          company: companyName
        )
      }
      return result.result
    } catch {
      return "Research failed: \(error.localizedDescription)"
    }
  }
  
  // MARK: - Filtering
  
  var filteredCompanies: [Company] {
    var result = companies
    
    if !companyFilter.nameQuery.isEmpty {
      result = result.filter {
        $0.name.localizedCaseInsensitiveContains(companyFilter.nameQuery)
      }
    }
    
    if !companyFilter.industryFilter.isEmpty {
      result = result.filter {
        ($0.industry ?? "").localizedCaseInsensitiveContains(companyFilter.industryFilter)
      }
    }
    
    if companyFilter.minEmployees > 0 {
      result = result.filter {
        ($0.employeeCount ?? 0) >= companyFilter.minEmployees
      }
    }
    
    return result
  }
  
  // MARK: - Score Company
  
  func scoreCompany(_ company: Company) -> LeadScore {
    return leadScoring.scoreLead(
      name: "",
      title: "",
      company: company.name,
      industry: company.industry ?? "",
      companySize: company.employeeRange ?? "",
      website: company.website ?? "",
      emailVerified: false,
      hasLinkedIn: false,
      researchAvailable: false
    )
  }
  
  // MARK: - Add to Leads
  
  func addContactAsLead(_ contact: Contact, company: Company) {
    let lead = Lead(
      name: contact.name,
      email: contact.email ?? "",
      company: company.name,
      title: contact.title ?? "",
      website: company.website
    )
    dataStore.addLead(lead)
    
    // Add to blocklist for future dedup
    leadScoring.addToBlocklist(
      domain: company.website ?? "",
      companyName: company.name
    )
  }
  
  // MARK: - Clear
  
  func clearResults() {
    companies = []
    selectedCompany = nil
    searchError = nil
  }
}

// MARK: - Company Filter

struct CompanyFilter {
  var nameQuery: String = ""
  var industryFilter: String = ""
  var minEmployees: Int = 0
  var maxEmployees: Int = 0
  var regionFilter: String = ""
}
