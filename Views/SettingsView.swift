import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Einstellungen")
                    .font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                perplexitySection
                googleSection
                sheetSection
                senderSection
                industrySection
                regionSection
                companySizeSection
                            dataManagementSection

                Button("Einstellungen speichern") {
                    vm.saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private var perplexitySection: some View {
        GroupBox("Perplexity API") {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key:").font(.caption).foregroundStyle(.secondary)
                SecureField("pplx-xxxxxxxx", text: $vm.settings.perplexityAPIKey)
                    .textFieldStyle(.roundedBorder)
                Link("Key holen: settings.perplexity.ai/api",
                     destination: URL(string: "https://settings.perplexity.ai/api")!)
                    .font(.caption)
            }
            .padding(8)
        }
    }

    private var googleSection: some View {
        GroupBox("Google Konto (Gmail + Sheets)") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Google Client ID", text: $vm.settings.googleClientID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Google Client Secret", text: $vm.settings.googleClientSecret)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if vm.authService.isAuthenticated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Verbunden: \(vm.authService.userEmail)")
                        Spacer()
                        Button("Abmelden") { vm.authService.logout() }
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Nicht verbunden")
                        Spacer()
                        Button("Google Login") {
                            vm.saveSettings()
                            vm.authService.startOAuthFlow()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(8)
        }
    }

    private var sheetSection: some View {
        GroupBox("Google Sheet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spreadsheet ID (aus der Sheet-URL):")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("1ABcDeFgHiJkLmNoPqRsTuVwXyZ...",
                          text: $vm.settings.spreadsheetID)
                    .textFieldStyle(.roundedBorder)
                Button("Sheet initialisieren (Header schreiben)") {
                    Task { await vm.initializeSheet() }
                }
                .disabled(vm.settings.spreadsheetID.isEmpty)
            }
            .padding(8)
        }
    }

    private var senderSection: some View {
        GroupBox("Absender") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $vm.settings.senderName)
                    .textFieldStyle(.roundedBorder)
                TextField("Email", text: $vm.settings.senderEmail)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(8)
        }
    }

    private var industrySection: some View {
        GroupBox("Industrien") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Industry.allCases) { industry in
                    Toggle(isOn: industryBinding(industry)) {
                        Label(industry.rawValue, systemImage: industry.icon)
                    }
                }
            }
            .padding(8)
        }
    }

    private var regionSection: some View {
        GroupBox("Regionen") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Region.allCases) { region in
                    Toggle(isOn: regionBinding(region)) {
                        Text("\(region.rawValue) (\(region.countries))")
                    }
                }
            }
            .padding(8)
        }
    }

    // NEW: CompanySize filter section
    private var companySizeSection: some View {
        GroupBox("Unternehmensgroesse") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unternehmen nach Groesse filtern")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(CompanySize.allCases) { size in
                    Toggle(isOn: companySizeBinding(size)) {
                        Label(size.rawValue, systemImage: size.icon)
                    }
                }
            }
            .padding(8)
        }
    }

    private func industryBinding(_ industry: Industry) -> Binding<Bool> {
        Binding(
            get: { vm.settings.selectedIndustries.contains(industry.rawValue) },
            set: { isOn in
                if isOn {
                    if !vm.settings.selectedIndustries.contains(industry.rawValue) {
                        vm.settings.selectedIndustries.append(industry.rawValue)
                    }
                } else {
                    vm.settings.selectedIndustries.removeAll { $0 == industry.rawValue }
                }
            }
        )
    }

    private func regionBinding(_ region: Region) -> Binding<Bool> {
        Binding(
            get: { vm.settings.selectedRegions.contains(region.rawValue) },
            set: { isOn in
                if isOn {
                    if !vm.settings.selectedRegions.contains(region.rawValue) {
                        vm.settings.selectedRegions.append(region.rawValue)
                    }
                } else {
                    vm.settings.selectedRegions.removeAll { $0 == region.rawValue }
                }
            }
        )
    }

    // NEW: CompanySize binding
    private func companySizeBinding(_ size: CompanySize) -> Binding<Bool> {
        Binding(
            get: { vm.settings.selectedCompanySizes.contains(size.rawValue) },
            set: { isOn in
                if isOn {
                    if !vm.settings.selectedCompanySizes.contains(size.rawValue) {
                        vm.settings.selectedCompanySizes.append(size.rawValue)
                    }
                } else {
                    vm.settings.selectedCompanySizes.removeAll { $0 == size.rawValue }
                }
            }
        )
    }

    // MARK: - Daten-Management
    @State private var purgeConfirmation = false

    private var dataManagementSection: some View {
        GroupBox("Daten-Management") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Datenbasis: \(vm.leads.count) Kontakte, \(vm.companies.count) Unternehmen")
                            .font(.callout)
                        Text("Alle Daten ausser bestimmtes Unternehmen loeschen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        purgeConfirmation = true
                    } label: {
                        Label("Bereinigen", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
        .alert("Datenbasis bereinigen?", isPresented: $purgeConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Bereinigen", role: .destructive) {
                vm.purgeAllExcept(companyName: "axlimits")
            }
        } message: {
            Text("Alle Kontakte und Unternehmen ausser 'axlimits' werden geloescht. Diese Aktion kann nicht rueckgaengig gemacht werden.")
        }
    }
}
