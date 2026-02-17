//
//  EmailDraftView.swift
//  HarpoOutreach
//
//  View for managing email drafts - edit, delete, send
//

import SwiftUI

struct EmailDraftView: View {
    @ObservedObject var vm: AppViewModel
    
    // Leads ohne Draft
    var draftsNeeded: [Lead] {
        vm.leads.filter { ($0.emailVerified || $0.isManuallyCreated) && $0.draftedEmail == nil }
    }
    
    // Leads mit Draft, noch nicht gesendet
    var draftsReady: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }
    }
    
    @State private var selectedLead: Lead?
    @State private var showingEditSheet = false
    @State private var showingSendConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var editSubject = ""
    @State private var emailBody = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Email Drafts")
                        .font(.largeTitle).bold()
                    Text("Emails bearbeiten, loeschen oder versenden")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Alle Emails generieren") {
                    Task { await vm.draftAllEmails() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftsNeeded.isEmpty || vm.isLoading)
            }
            .padding(24)
            
            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            
            Divider()
            
            if draftsReady.isEmpty && draftsNeeded.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Keine Drafts vorhanden.")
                        .foregroundStyle(.secondary)
                    Text("Verifiziere zuerst Emails im Prospecting-Tab.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    // SECTION 1: Drafts noch zu erstellen
                    if !draftsNeeded.isEmpty {
                        Section("Email noch zu erstellen (\(draftsNeeded.count))") {
                            ForEach(draftsNeeded) { lead in
                                HStack {
                                        Text(lead.name).bold()
                                                                            Text(lead.company).font(.caption)
                
                                        
                                    }
                                    Spacer()
                                    Button("Draft erstellen") {
                                        Task { await vm.draftEmailForLead(lead) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(vm.isLoading)
                                }
                            }
                        }
                    }
                    
                    // SECTION 2: Fertige Drafts - bearbeitbar, loeschbar, versendbar
                    if !draftsReady.isEmpty {
                        Section("Fertige Drafts (\(draftsReady.count))") {
                            ForEach(draftsReady) { lead in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Header
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(lead.name).bold()
                                            Text(lead.company).font(.caption).foregroundStyle(.secondary)
                                            Text(lead.email).font(.caption).foregroundStyle(.blue)
                                        }
                                        Spacer()
                                        
                                        // Status Badge
                                        if lead.isManuallyCreated {
                                            Text("Manuell")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    // Draft Preview
                                    if let draft = lead.draftedEmail {
                                        GroupBox {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Betreff: \(draft.subject)")
                                                    .font(.subheadline).bold()
                                                Text(draft.body)
                                                    .font(.caption)
                                                    .lineLimit(3)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    
                                    // Action Buttons
                                    HStack(spacing: 12) {
                                        Button {
                                            selectedLead = lead
                                            if let draft = lead.draftedEmail {
                                                editSubject = draft.subject
                                                emailBody = draft.body
                                            }
                                            showingEditSheet = true
                                        } label: {
                                            Label("Bearbeiten", systemImage: "pencil")
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button {
                                            selectedLead = lead
                                            showingSendConfirmation = true
                                        } label: {
                                            Label("Senden", systemImage: "paperplane")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        
                                        Spacer()
                                        
                                        Button(role: .destructive) {
                                            selectedLead = lead
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label("Loeschen", systemImage: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        // Edit Sheet
        .sheet(isPresented: $showingEditSheet) {
            if let lead = selectedLead {
                EditDraftSheet(
                    lead: lead,
                    subject: $editSubject,
                    emailBody: $emailBody,
                    onSave: { newSubject, newBody in
                        vm.updateDraft(for: lead, subject: newSubject, body: newBody)
                        showingEditSheet = false
                    },
                    onCancel: {
                        showingEditSheet = false
                    }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        // Send Confirmation
        .alert("Email senden?", isPresented: $showingSendConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") {
                if let lead = selectedLead {
                    Task {
                        await vm.sendEmail(to: lead)
                    }
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll die Email an \(lead.name) (\(lead.email)) gesendet werden?")
            }
        }
        // Delete Confirmation
        .alert("Draft loeschen?", isPresented: $showingDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loeschen", role: .destructive) {
                if let lead = selectedLead {
                    vm.deleteDraft(for: lead)
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll der Email-Draft fuer \(lead.name) geloescht werden?")
            }
        }
    }
}

// MARK: - Edit Draft Sheet
struct EditDraftSheet: View {
    let lead: Lead
    @Binding var subject: String
    @Binding var emailBody: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Email bearbeiten")
                        .font(.headline)
                    Text("An: \(lead.name) <\(lead.email)>")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { onCancel() }
                    .buttonStyle(.bordered)
                Button("Speichern") { onSave(subject, emailBody) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Betreff") {
                    TextField("Betreff", text: $subject)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Nachricht") {
                    TextEditor(text: $emailBody)
                        .frame(minHeight: 250)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    EmailDraftView(vm: AppViewModel())
}
