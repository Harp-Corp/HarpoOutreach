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
        VStack(spacing: 12) { headerRow; industryFilterChips; sizeFilterChips; regionFilterChips }{ 
            headerRow
            industryFilterChips
            sizeFilterChips
            regionFilterChips
            
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
        .padding(24)
    }
    }
                    
