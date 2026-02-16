//
//  ManualEntryView.swift
//  HarpoOutreach
//
//  View for manually adding companies and contacts
//

import SwiftUI

struct ManualEntryView: View {
    @ObservedObject var vm: AppViewModel
    
    // Company fields
    @State private var companyName = ""
    @State private var industry: Industry = .healthcare
    @State private var region: Region = .dach
    @State private var website = ""
    @State private var companyDescription = ""
    
    // Contact fields
    @State private var contactName = ""
    @State private var contactTitle = ""
    @State private var contactEmail = ""
    @State private var linkedInURL = ""
    @State private var responsibility = ""
    
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Manueller Eintrag")
                        .font(.largeTitle)
                        .bold()
                    Text("Unternehmen und Ansprechpartner direkt hinzufuegen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Company Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Unternehmensinformationen")
                                .font(.headline)
                            
                            TextField("Firmenname*", text: $companyName)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Branche*")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Branche", selection: $industry) {
                                        ForEach(Industry.allCases, id: \.self) { ind in
                                            Text(ind.rawValue).tag(ind)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Region*")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Region", selection: $region) {
                                        ForEach(Region.allCases, id: \.self) { reg in
                                            Text(reg.rawValue).tag(reg)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            
                            TextField("Website", text: $website)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            
                            TextField("Beschreibung", text: $companyDescription, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                    }
                    
                    // Contact Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Ansprechpartner")
                                .font(.headline)
                            
                            TextField("Name*", text: $contactName)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            
                            TextField("Position", text: $contactTitle)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            
                            TextField("E-Mail*", text: $contactEmail)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .multilineTextAlignment(.leading)
                            
                            TextField("LinkedIn URL", text: $linkedInURL)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .multilineTextAlignment(.leading)
                            
                            TextField("Verantwortungsbereich", text: $responsibility, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        Button("Zuruecksetzen", role: .cancel) {
                            resetForm()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Speichern und Hinzufuegen") {
                            Task {
                                await saveLead()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isFormValid)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .alert("Erfolgreich gespeichert", isPresented: $showingSuccess) {
            Button("OK") {
                resetForm()
            }
        } message: {
            Text("Der Kontakt wurde erfolgreich hinzugefuegt und ins Google Sheet geschrieben.")
        }
        .alert("Fehler", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Validation
    private var isFormValid: Bool {
        !companyName.isEmpty && !contactName.isEmpty && !contactEmail.isEmpty
    }
    
    // MARK: - Actions
    private func resetForm() {
        companyName = ""
        website = ""
        companyDescription = ""
        contactName = ""
        contactTitle = ""
        contactEmail = ""
        linkedInURL = ""
        responsibility = ""
    }
    
    private func saveLead() async {
        // Create company
        let company = Company(
            name: companyName,
            industry: industry.rawValue,
            region: region.rawValue,
            website: website,
            description: companyDescription
        )
        
        // Create lead with isManuallyCreated = true
        var lead = Lead(
            name: contactName,
            title: contactTitle,
            company: companyName,
            email: contactEmail,
            emailVerified: true,  // Manuelle Kontakte sind automatisch verifiziert
            linkedInURL: linkedInURL,
            responsibility: responsibility,
            status: .identified,
            source: "Manual Entry",
            isManuallyCreated: true  // NEU: Flag fuer manuelle Erstellung
        )
        
        // Add to ViewModel
        await MainActor.run {
            vm.companies.append(company)
            vm.leads.append(lead)
            vm.saveLeads()
            vm.saveCompanies()
        }
        
        // Save to Google Sheets if configured
        if !vm.settings.spreadsheetID.isEmpty {
            do {
                try await vm.writeLeadToSheet(lead)
                showingSuccess = true
            } catch {
                errorMessage = "Gespeichert, aber Fehler beim Schreiben ins Sheet: \(error.localizedDescription)"
                showingError = true
            }
        } else {
            showingSuccess = true
        }
    }
}

#Preview {
    ManualEntryView(vm: AppViewModel())
}
