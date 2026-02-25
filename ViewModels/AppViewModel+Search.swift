import Foundation

// MARK: - Search Wrapper + Cancellation Support
extension AppViewModel {

    /// Starts company search as cancellable task.
    /// Called from ProspectingView instead of findCompanies() directly.
    func startFindCompanies(forIndustry: Industry? = nil) {
        currentTask?.cancel()
        currentTask = Task {
            await findCompaniesWithCancellation(forIndustry: forIndustry)
        }
    }

    /// Region-aware, cancellable version of findCompanies
    private func findCompaniesWithCancellation(forIndustry: Industry? = nil) async {
        guard !settings.perplexityAPIKey.isEmpty else {
            errorMessage = "Perplexity API Key fehlt."; return
        }
        isLoading = true; errorMessage = ""; companies = []

        let industries: [Industry]
        if let specific = forIndustry ?? selectedIndustryFilter {
            industries = [specific]
        } else {
            industries = Industry.allCases.filter { settings.selectedIndustries.contains($0.rawValue) }
        }

        // Use selectedRegionFilter if set, otherwise fall back to settings
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
                    let found = try await pplxService.findCompanies(
                        industry: industry, region: region,
                        apiKey: settings.perplexityAPIKey
                    )
                    let newOnes = found.filter { new in
                        !companies.contains { $0.name.lowercased() == new.name.lowercased() }
                    }
                    companies.append(contentsOf: newOnes)
                } catch {
                    if !Task.isCancelled {
                        errorMessage = "Error \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)"
                    }
                }
            }
        }

        if Task.isCancelled {
            currentStep = "Search cancelled"; isLoading = false; return
        }

        currentStep = "\(companies.count) companies found"
        refilterCompanies()
        saveCompanies()
        isLoading = false
    }

    /// Re-applies size filter + existing-lead exclusion on current companies.
    /// Called when size filter chips change in ProspectingView.
    func refilterCompanies() {
        let selectedSizes = CompanySize.allCases.filter {
            settings.selectedCompanySizes.contains($0.rawValue)
        }
        companies = companies.applySearchFilters(
            selectedSizes: selectedSizes, existingLeads: leads
        )
        currentStep = "\(companies.count) companies after filtering"
    }
}
