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

  var body: some View {
    VStack(spacing: 0) {
      // KPI Cards
      HStack(spacing: 16) {
        kpiCard(title: "Emails gesendet", value: "\(emailsSent)", icon: "paperplane.fill", color: .blue)
        kpiCard(title: "Follow-Ups", value: "\(followUpsSent)", icon: "arrow.uturn.forward", color: .orange)
        kpiCard(title: "Antworten", value: "\(repliesReceived)", icon: "envelope.open.fill", color: .green)
        kpiCard(title: "Opt-Outs", value: "\(optedOut)", icon: "exclamationmark.triangle.fill", color: .red)
      }
      .padding()

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
        Button("Aktualisieren") {
          outreachLog = DatabaseService.shared.loadOutreachLog()
        }
        .buttonStyle(.bordered)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Log Table
      if filteredLog.isEmpty {
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
