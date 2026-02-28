import SwiftUI

struct ProspectingView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showManualCompanySheet = false
    @State private var showManualContactSheet = false
    @State private var selectedCompanyForContact: Company?

    var body: some View {
        VStack(spacing: 0) {
            ProspectingHeaderView(vm: vm)
            Divider()
            HStack(spacing: 0) {
                ProspectingCompanyList(vm: vm, showManualCompanySheet: $showManualCompanySheet, showManualContactSheet: $showManualContactSheet, selectedCompanyForContact: $selectedCompanyForContact)
                Divider()
                ProspectingContactList(vm: vm)
            }
        }
        .sheet(isPresented: $showManualCompanySheet) {
            ManualCompanyEntryView(vm: vm)
        }
        .sheet(item: $selectedCompanyForContact) { company in
            ManualContactEntryView(vm: vm, company: company)
        }
    }
}

// MARK: - Header with Industry Filter + CompanySize Filter
struct ProspectingHeaderView: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        VStack(spacing: 12) { headerRow; industryFilterChips; sizeFilterChips; regionFilterChips }.padding(24)
                    
            // Start/Stop Search Button
            Button(action: {
                if vm.isLoading {
                    vm.cancelSearch()
                } else {
                    vm.startFindCompanies()
                }
            }) {
                Text(vm.isLoading ? "Suche abbrechen" : "Start Suche")
                    .font(.system(size: 16, design: .default))
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isLoading ? Color.red : Color.accentColor)
    }
    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Prospecting").font(.largeTitle).bold()
                Text("Find companies and contacts").foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isLoading { ProgressView(); Text(vm.currentStep).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var industryFilterChips: some View {
        HStack(spacing: 8) {
            Button(action: { vm.selectedIndustryFilter = nil }) { Text("All Industries") }
            .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
            .background(vm.selectedIndustryFilter == nil ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundColor(vm.selectedIndustryFilter == nil ? .white : .primary)
            .cornerRadius(8).buttonStyle(.plain)
            ForEach(Industry.allCases) { industry in
                Button(action: { vm.selectedIndustryFilter = industry }) {
                    HStack(spacing: 4) { Image(systemName: industry.icon).font(.caption2); Text(industry.shortName).font(.caption) }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(vm.selectedIndustryFilter == industry ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(vm.selectedIndustryFilter == industry ? .white : .primary)
                .cornerRadius(8).buttonStyle(.plain)
            }
        }
    }
    private var sizeFilterChips: some View {
        HStack(spacing: 8) {
            Text("Groesse:").font(.caption).foregroundStyle(.secondary)
            ForEach(CompanySize.allCases) { size in
                let isSelected = vm.settings.selectedCompanySizes.contains(size.rawValue)
                Button(action: {
                    if isSelected { vm.settings.selectedCompanySizes.removeAll { $0 == size.rawValue } }
                    else { vm.settings.selectedCompanySizes.append(size.rawValue) }
                    vm.refilterCompanies()
                }) {
                    HStack(spacing: 4) { Image(systemName: size.icon).font(.caption2); Text(size.shortName).font(.caption) }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSelected ? Color.purple.opacity(0.8) : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6).buttonStyle(.plain)
            }
        }
    }
    private var regionFilterChips: some View {
        HStack(spacing: 8) {
            Text("Region:").font(.caption).foregroundStyle(.secondary)
            Button(action: { vm.selectedRegionFilter = nil }) { Text("Alle") }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
            .background(vm.selectedRegionFilter == nil ? Color.green.opacity(0.8) : Color.gray.opacity(0.2))
            .foregroundColor(vm.selectedRegionFilter == nil ? .white : .primary)
            .cornerRadius(6).buttonStyle(.plain)
            ForEach(Region.allCases) { region in
                Button(action: { vm.selectedRegionFilter = region }) { Text(region.rawValue).font(.caption) }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(vm.selectedRegionFilter == region ? Color.green.opacity(0.8) : Color.gray.opacity(0.2))
                .foregroundColor(vm.selectedRegionFilter == region ? .white : .primary)
                .cornerRadius(6).buttonStyle(.plain)
            }
        }
    }


