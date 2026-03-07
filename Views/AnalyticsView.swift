import SwiftUI

// MARK: - AnalyticsView: Combined Pipeline + Google Sheet + Outreach Log
// Feature 5: Wer wurde wann mit was angeschrieben? Rueckmeldungen? Unsubscribes?
struct AnalyticsView: View {
  @ObservedObject var vm: AppViewModel
  @State private var selectedSegment = 0
  @State private var outreachLog: [OutreachLogEntry] = []
  @State private var filterAction: String = "all"

  var body: some View {
    VStack(spacing: 0) {
      // Header with segment picker
      HStack {
        Text("Analytics").font(.largeTitle).bold()
        Spacer()
        Picker("", selection: $selectedSegment) {
          Text("Pipeline").tag(0)
          Text("Outreach Log").tag(1)
          Text("Google Sheet").tag(2)
        }
        .pickerStyle(.segmented)
        .frame(width: 400)
      }
      .padding()

      Divider()

      // Content based on segment
      switch selectedSegment {
      case 0: PipelineContent(vm: vm)
      case 1: OutreachLogContent(vm: vm, outreachLog: $outreachLog, filterAction: $filterAction)
      case 2: SheetContent(vm: vm)
      default: PipelineContent(vm: vm)
      }
    }
    .onAppear {
      outreachLog = DatabaseService.shared.loadOutreachLog()
    }
  }
}

// MARK: - Outreach Log Content (Feature 5)
struct OutreachLogContent: View {
  @ObservedObject var vm: AppViewModel
  @Binding var outreachLog: [OutreachLogEntry]
  @Binding var filterAction: String

  @State private var clearBlocklistConfirm = false
  @State private var checkingReplies = false

  private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    df.locale = Locale(identifier: "de_DE")
    return df
  }()

  var filteredLog: [OutreachLogEntry] {
    if filterAction == "all" { return outreachLog }
    return outreachLog.filter { $0.action == filterAction }
  }

  var emailsSent: Int { outreachLog.filter { $0.action == "email_sent" }.count }
  var repliesReceived: Int { outreachLog.filter { $0.action == "reply_received" }.count }
  var optedOut: Int { outreachLog.filter { $0.action == "opted_out" }.count }
  var followUpsSent: Int { outreachLog.filter { $0.action == "follow_up_sent" }.count }

  /// Sent leads with stored gmailThreadId
  private var sentLeadsWithThreads: [Lead] {
    vm.leads.filter { !$0.gmailThreadId.isEmpty && $0.dateEmailSent != nil }
  }

  var body: some View {
    VStack(spacing: 0) {
      // KPI Cards
      HStack(spacing: 16) {
        kpiCard(title: "Emails gesendet", value: "\(emailsSent)", icon: "paperplane.fill", color: .blue)
        kpiCard(title: "Follow-Ups", value: "\(followUpsSent)", icon: "arrow.uturn.forward", color: .orange)
        kpiCard(title: "Antworten", value: "\(repliesReceived)", icon: "envelope.open.fill", color: .green)
        kpiCard(title: "Opt-Outs", value: "\(optedOut)", icon: "exclamationmark.triangle.fill", color: .red)
        kpiCard(title: "Blocklist", value: "\(vm.statsBlocked)", icon: "hand.raised.fill", color: .purple)
      }
      .padding()

      // Action bar: reply check, blocklist management
      HStack(spacing: 12) {
        // Thread-based reply check
        Button(action: {
          checkingReplies = true
          Task {
            await vm.checkRepliesViaThreads()
            outreachLog = DatabaseService.shared.loadOutreachLog()
            checkingReplies = false
          }
        }) {
          HStack(spacing: 4) {
            if checkingReplies {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.triangle.branch")
            }
            Text(checkingReplies ? "Prüfe Threads..." : "Antworten prüfen (Thread)")
          }
          .font(.caption)
        }
        .buttonStyle(.bordered)
        .disabled(checkingReplies || sentLeadsWithThreads.isEmpty)

        // Thread tracking status
        if !sentLeadsWithThreads.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.caption2).foregroundStyle(.green)
            Text("\(sentLeadsWithThreads.count) Threads aktiv")
              .font(.caption2).foregroundStyle(.secondary)
          }
        }

        Spacer()

        // Blocklist info + clear button
        if vm.statsBlocked > 0 {
          Text("\(vm.statsBlocked) in Blocklist")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Button(action: { clearBlocklistConfirm = true }) {
          Label("Blocklist leeren", systemImage: "hand.raised.slash")
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.red)
        .disabled(vm.statsBlocked == 0)

        // Refresh log
        Button("Aktualisieren") {
          outreachLog = DatabaseService.shared.loadOutreachLog()
        }
        .buttonStyle(.bordered)
        .font(.caption)
      }
      .padding(.horizontal)
      .padding(.bottom, 4)

      // Filter bar
      HStack {
        Text("Filter:").font(.caption).foregroundStyle(.secondary)
        Picker("", selection: $filterAction) {
          Text("Alle").tag("all")
          Text("Email gesendet").tag("email_sent")
          Text("Follow-Up").tag("follow_up_sent")
          Text("Antwort erhalten").tag("reply_received")
          Text("Opt-Out (Red Flag)").tag("opted_out")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 600)
        Spacer()
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Sent leads list with Reset/Resend per lead
      if vm.leads.filter({ $0.dateEmailSent != nil }).isEmpty && filteredLog.isEmpty {
        VStack {
          Spacer()
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 48)).foregroundStyle(.secondary)
          Text("Keine Outreach-Eintraege gefunden.")
          Text("Sende Emails, um Aktivitaeten zu protokollieren.")
            .font(.caption).foregroundStyle(.tertiary)
          Spacer()
        }
      } else {
        // Split: sent leads with actions (top) + outreach log table (bottom)
        VSplitView {
          // Sent leads with per-lead Reset/Resend
          sentLeadsSection
            .frame(minHeight: 120, idealHeight: 200)

          // Outreach log table
          outreachLogTable
            .frame(minHeight: 200)
        }
      }
    }
    .alert("Blocklist leeren?", isPresented: $clearBlocklistConfirm) {
      Button("Abbrechen", role: .cancel) { }
      Button("Leeren", role: .destructive) {
        vm.clearAllBlocklist()
        outreachLog = DatabaseService.shared.loadOutreachLog()
      }
    } message: {
      Text("Alle \(vm.statsBlocked) Einträge in der Blocklist werden gelöscht und alle opted_out-Flags werden zurückgesetzt. Diese Aktion kann nicht rückgängig gemacht werden.")
    }
  }

  // MARK: - Sent Leads Section with Reset/Resend
  private var sentLeadsSection: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Gesendete Emails")
          .font(.caption.bold()).foregroundStyle(.secondary)
        Spacer()
        Text("\(vm.leads.filter { $0.dateEmailSent != nil }.count) Emails")
          .font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.vertical, 6)

      Divider()

      if vm.leads.filter({ $0.dateEmailSent != nil }).isEmpty {
        HStack {
          Spacer()
          Text("Noch keine Emails gesendet.")
            .font(.caption).foregroundStyle(.tertiary)
          Spacer()
        }
        .padding()
      } else {
        List {
          ForEach(vm.leads.filter { $0.dateEmailSent != nil }.sorted(by: {
            ($0.dateEmailSent ?? .distantPast) > ($1.dateEmailSent ?? .distantPast)
          })) { lead in
            sentLeadRow(lead: lead)
          }
        }
        .listStyle(.plain)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func sentLeadRow(lead: Lead) -> some View {
    HStack(spacing: 8) {
      // Status dot
      Circle()
        .fill(lead.optedOut ? Color.red : (lead.replyReceived.isEmpty ? Color.blue : Color.green))
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(lead.name)
            .font(.callout)
            .lineLimit(1)
          Text("@ \(lead.company)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          // Thread ID indicator
          if !lead.gmailThreadId.isEmpty {
            Image(systemName: "arrow.triangle.branch")
              .font(.caption2).foregroundStyle(.indigo)
              .help("Thread ID: \(lead.gmailThreadId)")
          }
        }

        // Reply text (if any)
        if !lead.replyReceived.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "envelope.open.fill")
              .font(.caption2).foregroundStyle(.green)
            Text(lead.replyReceived)
              .font(.caption2)
              .foregroundStyle(.green)
              .lineLimit(2)
          }
        }

        if let sentDate = lead.dateEmailSent {
          Text("Gesendet: \(sentDate.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }

      Spacer()

      // Opt-out badge
      if lead.optedOut {
        Text("Opt-Out")
          .font(.system(size: 9))
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(Color.red.opacity(0.12))
          .cornerRadius(3)
          .foregroundStyle(.red)
      } else if !lead.replyReceived.isEmpty {
        Text("Geantwortet")
          .font(.system(size: 9))
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(Color.green.opacity(0.12))
          .cornerRadius(3)
          .foregroundStyle(.green)
      }

      // Erneut senden
      Button(action: {
        vm.resendLead(id: lead.id)
      }) {
        Label("Erneut senden", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      // Zurücksetzen
      Button(action: {
        vm.resetLead(id: lead.id)
      }) {
        Label("Zurücksetzen", systemImage: "trash")
          .font(.caption)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .foregroundStyle(.red)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Outreach Log Table
  private var outreachLogTable: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Outreach Log")
          .font(.caption.bold()).foregroundStyle(.secondary)
        Spacer()
        Text("\(filteredLog.count) Einträge")
          .font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.vertical, 6)

      Divider()

      if filteredLog.isEmpty {
        VStack {
          Spacer()
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 36)).foregroundStyle(.secondary)
          Text("Keine Einträge für diesen Filter.")
            .font(.caption).foregroundStyle(.tertiary)
          Spacer()
        }
      } else {
        Table(filteredLog) {
          TableColumn("Datum") { entry in
            Text(dateFormatter.string(from: entry.timestamp))
              .font(.caption)
          }
          .width(min: 120, ideal: 150)

          TableColumn("Aktion") { entry in
            HStack(spacing: 4) {
              actionIcon(entry.action)
              Text(actionLabel(entry.action))
                .font(.caption)
            }
          }
          .width(min: 100, ideal: 130)

          TableColumn("Name") { entry in
            Text(entry.leadName)
              .font(.caption)
          }
          .width(min: 120, ideal: 150)

          TableColumn("Unternehmen") { entry in
            Text(entry.company)
              .font(.caption)
          }
          .width(min: 120, ideal: 150)

          TableColumn("Email") { entry in
            Text(entry.email)
              .font(.caption)
              .foregroundStyle(entry.action == "opted_out" ? .red : .primary)
          }
          .width(min: 150, ideal: 200)

          TableColumn("Betreff") { entry in
            Text(entry.subject)
              .font(.caption)
              .lineLimit(1)
          }
          .width(min: 150, ideal: 250)

          TableColumn("Kanal") { entry in
            Text(entry.channel)
              .font(.caption)
          }
          .width(min: 60, ideal: 80)
        }
      }
    }
  }

  @ViewBuilder
  private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
    VStack(spacing: 8) {
      HStack {
        Image(systemName: icon)
          .foregroundStyle(color)
        Spacer()
      }
      Text(value)
        .font(.system(size: 32, weight: .bold, design: .rounded))
        .foregroundStyle(color)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(color.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func actionIcon(_ action: String) -> some View {
    switch action {
    case "email_sent":
      return Image(systemName: "paperplane.fill").foregroundStyle(.blue)
    case "follow_up_sent":
      return Image(systemName: "arrow.uturn.forward").foregroundStyle(.orange)
    case "reply_received":
      return Image(systemName: "envelope.open.fill").foregroundStyle(.green)
    case "opted_out":
      return Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    default:
      return Image(systemName: "circle.fill").foregroundStyle(.gray)
    }
  }

  private func actionLabel(_ action: String) -> String {
    switch action {
    case "email_sent": return "Email gesendet"
    case "follow_up_sent": return "Follow-Up"
    case "reply_received": return "Antwort"
    case "opted_out": return "Opt-Out"
    default: return action
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
            if let header = vm.sheetData.first {
              HStack(spacing: 0) {
                ForEach(0..<header.count, id: \.self) { col in
                  Text(header[col])
                    .font(.caption.bold())
                    .frame(width: 140, alignment: .leading)
                    .padding(6)
                    .background(Color.secondary.opacity(0.15))
                }
              }
            }
            ForEach(1..<vm.sheetData.count, id: \.self) { row in
              HStack(spacing: 0) {
                ForEach(0..<vm.sheetData[row].count, id: \.self) { col in
                  Text(vm.sheetData[row][col])
                    .font(.caption)
                    .frame(width: 140, alignment: .leading)
                    .padding(6)
                }
              }
              Divider()
            }
          }
        }
      }
    }
  }
}
