import Foundation
import SwiftUI

// MARK: - AppViewModel+Prospecting
// Handles: company/contact discovery, email verification, filtering, manual entry

extension AppViewModel {

    // MARK: - 1) Find Companies (original, non-cancellable variant)
    func findCompanies(forIndustry: Industry? = nil) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true; errorMessage = ""; companies = []
        let industries: [Industry]
        if let specific = forIndustry ?? selectedIndustryFilter {
            industries = [specific]
        } else {
            industries = Industry.allCases.filter { settings.selectedIndustries.contains($0.rawValue) }
        }
        let regions = Region.allCases.filter { settings.selectedRegions.contains($0.rawValue) }
        for industry in industries {
            for region in regions {
                currentStep = "Searching \(industry.shortName) in \(region.rawValue)..."
                do {
                    let found = try await pplxService.findCompanies(industry: industry, region: region, apiKey: settings.perplexityAPIKey)
                    let newOnes = found.filter { new in
                        !companies.contains { $0.name.lowercased() == new.name.lowercased() }
                        && !DatabaseService.shared.companyExists(name: new.name)
                    }
                    companies.append(contentsOf: newOnes)
                } catch {
                    errorMessage = "Error \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)"
                }
            }
        }
        currentStep = "\(companies.count) companies found"
        let selectedSizes = CompanySize.allCases.filter { settings.selectedCompanySizes.contains($0.rawValue) }
        companies = companies.applySearchFilters(selectedSizes: selectedSizes, existingLeads: leads)
        currentStep = "\(companies.count) companies after filtering"
        saveCompanies()
        isLoading = false
    }

    // MARK: - 1b) Find Companies with Cancellation Support
    func startFindCompanies(forIndustry: Industry? = nil) {
        currentTask?.cancel()
        currentTask = Task {
            await findCompaniesWithCancellation(forIndustry: forIndustry)
        }
    }

    func findCompaniesWithCancellation(forIndustry: Industry? = nil) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true; errorMessage = ""; companies = []
        let industries: [Industry]
        if let specific = forIndustry ?? selectedIndustryFilter {
            industries = [specific]
        } else {
            industries = Industry.allCases.filter { settings.selectedIndustries.contains($0.rawValue) }
        }
        let regions: [Region]
        if let specificRegion = selectedRegionFilter {
            regions = [specificRegion]
        } else {
            regions = Region.allCases.filter { settings.selectedRegions.contains($0.rawValue) }
        }
        for industry in industries {
            guard !Task.isCancelled else { break }
            for region in regions {
                guard !Task.isCancelled else { break }
                currentStep = "Searching \(industry.shortName) in \(region.rawValue)..."
                do {
                    let found = try await pplxService.findCompanies(industry: industry, region: region, apiKey: settings.perplexityAPIKey)
                    let newOnes = found.filter { new in
                        !companies.contains { $0.name.lowercased() == new.name.lowercased() }
                        && !DatabaseService.shared.companyExists(name: new.name)
                    }
                    companies.append(contentsOf: newOnes)
                } catch {
                    if !Task.isCancelled {
                        errorMessage = "Error \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)"
                    }
                }
            }
        }
        if Task.isCancelled { currentStep = "Search cancelled"; isLoading = false; return }
        currentStep = "\(companies.count) companies found"
        refilterCompanies()
        saveCompanies()
        isLoading = false
    }

    // MARK: - 1c) Refilter Companies
    func refilterCompanies() {
        let selectedSizes = CompanySize.allCases.filter { settings.selectedCompanySizes.contains($0.rawValue) }
        companies = companies.applySearchFilters(selectedSizes: selectedSizes, existingLeads: leads)
        currentStep = "\(companies.count) companies after filtering"
    }

    // MARK: - 2) Find Contacts
    func findContacts(for company: Company) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true; currentStep = "Searching contacts at \(company.name)..."
        currentSearchContacts = []
        do {
            let found = try await pplxService.findContacts(company: company, apiKey: settings.perplexityAPIKey)
            currentSearchContacts = found
            // Auto-add to main leads - dedup via DatabaseService + in-memory check
            let newLeads = found.filter { newLead in
                !leads.contains {
                    $0.name.lowercased() == newLead.name.lowercased()
                    && $0.company.lowercased() == newLead.company.lowercased()
                }
                && !DatabaseService.shared.leadExists(name: newLead.name, company: newLead.company)
            }
            leads.append(contentsOf: newLeads)
            saveLeads()
            currentStep = "\(found.count) contacts found at \(company.name) (\(newLeads.count) new)"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func findContactsForAll() async {
        currentSearchContacts = []
        for company in companies { await findContacts(for: company) }
    }

    // MARK: - 3) Email Verification
    func verifyEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        isLoading = true; currentStep = "Verifying email for \(leads[idx].name)..."
        do {
            let result = try await pplxService.verifyEmail(lead: leads[idx], apiKey: settings.perplexityAPIKey)
            leads[idx].email = result.email
            leads[idx].emailVerified = result.verified
            leads[idx].verificationNotes = result.notes
            leads[idx].status = result.verified ? .contacted : .identified
            saveLeads()
            currentStep = result.verified ? "Email verified: \(result.email)" : "Not verified: \(result.notes)"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func verifyAllEmails() async {
        for lead in leads.filter({ !$0.emailVerified }) { await verifyEmail(for: lead.id) }
    }

    // MARK: - Manual Entry
    func addCompanyManually(_ company: Company) {
        let alreadyInMemory = companies.contains { $0.name.lowercased() == company.name.lowercased() }
        let alreadyInDB = DatabaseService.shared.companyExists(name: company.name)
        if !alreadyInMemory && !alreadyInDB {
            companies.append(company)
            saveCompanies()
            statusMessage = "Company \(company.name) added"
        } else {
            errorMessage = "Company \(company.name) already exists"
        }
    }

    func addLeadManually(_ lead: Lead) {
        let alreadyInMemory = leads.contains {
            $0.name.lowercased() == lead.name.lowercased()
            && $0.company.lowercased() == lead.company.lowercased()
        }
        let alreadyInDB = DatabaseService.shared.leadExists(name: lead.name, company: lead.company)
        if !alreadyInMemory && !alreadyInDB {
            leads.append(lead)
            saveLeads()
            statusMessage = "Contact \(lead.name) added"
        } else {
            errorMessage = "Contact \(lead.name) at \(lead.company) already exists"
        }
    }

    func addTestCompany() {
        let testCompany = Company(
            name: "Harpocrates Corp",
            industry: "K - Finanzdienstleistungen",
            region: "DACH",
            website: "https://harpocrates-corp.com",
            description: "RegTech Startup"
        )
        if !companies.contains(where: { $0.name == "Harpocrates Corp" }) {
            companies.append(testCompany)
            saveCompanies()
            statusMessage = "Test company added"
        }
        let testLead = Lead(
            name: "Martin Foerster",
            title: "CEO & Founder",
            company: testCompany.name,
            email: "mf@harpocrates-corp.com",
            emailVerified: true,
            linkedInURL: "https://linkedin.com/in/martinfoerster",
            status: .contacted,
            source: "test",
            isManuallyCreated: true
        )
        if !leads.contains(where: { $0.email == "mf@harpocrates-corp.com" }) {
            leads.append(testLead)
            saveLeads()
            statusMessage = "Test contact added"
        }
    }
}
