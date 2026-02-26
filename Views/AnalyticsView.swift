import SwiftUI

// MARK: - AnalyticsView: Combined Pipeline + Google Sheet
struct AnalyticsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedSegment = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with segment picker
            HStack {
                Text("Analytics").font(.largeTitle).bold()
                Spacer()
                Picker("", selection: $selectedSegment) {
                    Text("Pipeline").tag(0)
                    Text("Google Sheet").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding()

            Divider()

            // Content based on segment
            switch selectedSegment {
            case 0: PipelineContent(vm: vm)
            case 1: SheetContent(vm: vm)
            default: PipelineContent(vm: vm)
            }
        }
    }
}

// MARK: - Pipeline Content (wraps OutreachPipelineView content)
struct PipelineContent: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        OutreachPipelineView(vm: vm)
    }
}

// MARK: - Sheet Content (wraps SheetLogView content)
struct SheetContent: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Google Sheet Log")
                        .font(.headline)
                    Text("Spreadsheet: \(vm.settings.spreadsheetID.isEmpty ? "(nicht konfiguriert)" : String(vm.settings.spreadsheetID.prefix(20)) + "...")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sheet aktualisieren") {
                    Task { await vm.refreshSheetData() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.settings.spreadsheetID.isEmpty || vm.isLoading)
            }
            .padding()

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption)
                }
                .padding(.horizontal, 24)
            }

            Divider()

            if vm.settings.spreadsheetID.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "tablecells")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Spreadsheet ID nicht konfiguriert.")
                    Text("Gehe zu Einstellungen und trage die Sheet-ID ein.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else if vm.sheetData.isEmpty {
                VStack {
                    Spacer()
                    Text("Noch keine Daten im Sheet.")
                    Text("Sende Emails, um Daten zu loggen.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Header row
                        if let header = vm.sheetData.first {
                            HStack(spacing: 0) {
                                ForEach(0..<header.count, id: \.self) { col in
                                    Text(header[col])
                                        .font(.caption).bold()
                                        .frame(minWidth: 120, alignment: .leading)
                                        .padding(8)
                                        .background(Color.gray.opacity(0.2))
                                        .border(Color.gray.opacity(0.3), width: 0.5)
                                }
                            }
                        }
                        // Data rows
                        ForEach(1..<vm.sheetData.count, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<vm.sheetData[row].count, id: \.self) { col in
                                    Text(vm.sheetData[row][col])
                                        .font(.caption)
                                        .frame(minWidth: 120, alignment: .leading)
                                        .padding(8)
                                        .background(row % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                                        .border(Color.gray.opacity(0.2), width: 0.5)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}
