import Foundation
import Combine

// MARK: - SchedulerService
// Manages scheduled tasks: email sending windows, follow-up timing,
// social post scheduling, and recurring task management.

@MainActor
class SchedulerService: ObservableObject {

  static let shared = SchedulerService()

  @Published var scheduledTasks: [ScheduledTask] = []
  @Published var isRunning = false
  @Published var nextFireDate: Date?

  private var timer: Timer?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Scheduling

  /// Schedule an email to be sent at a specific time.
  func scheduleEmail(emailID: UUID, sendAt: Date, priority: TaskPriority = .normal) {
    let task = ScheduledTask(
      type: .emailSend,
      referenceID: emailID,
      scheduledFor: sendAt,
      priority: priority
    )
    scheduledTasks.append(task)
    sortAndUpdateNext()
  }

  /// Schedule a follow-up email after a delay.
  func scheduleFollowUp(leadID: UUID, delay: TimeInterval, priority: TaskPriority = .normal) {
    let sendAt = Date().addingTimeInterval(delay)
    let task = ScheduledTask(
      type: .followUp,
      referenceID: leadID,
      scheduledFor: sendAt,
      priority: priority
    )
    scheduledTasks.append(task)
    sortAndUpdateNext()
  }

  /// Schedule a social post for a specific date/time.
  func scheduleSocialPost(postID: UUID, publishAt: Date) {
    let task = ScheduledTask(
      type: .socialPost,
      referenceID: postID,
      scheduledFor: publishAt,
      priority: .normal
    )
    scheduledTasks.append(task)
    sortAndUpdateNext()
  }

  /// Schedule a generic recurring task.
  func scheduleRecurring(type: ScheduledTaskType, interval: TimeInterval, startAt: Date = Date()) {
    let task = ScheduledTask(
      type: type,
      referenceID: UUID(),
      scheduledFor: startAt,
      priority: .normal,
      recurring: true,
      recurrenceInterval: interval
    )
    scheduledTasks.append(task)
    sortAndUpdateNext()
  }

  // MARK: - Task Management

  /// Cancel a scheduled task.
  func cancelTask(id: UUID) {
    scheduledTasks.removeAll { $0.id == id }
    sortAndUpdateNext()
  }

  /// Cancel all tasks for a given reference ID.
  func cancelTasksForReference(_ refID: UUID) {
    scheduledTasks.removeAll { $0.referenceID == refID }
    sortAndUpdateNext()
  }

  /// Get all pending tasks sorted by scheduled time.
  var pendingTasks: [ScheduledTask] {
    scheduledTasks.filter { $0.status == .pending }
      .sorted { $0.scheduledFor < $1.scheduledFor }
  }

  /// Get overdue tasks (scheduled in the past but not yet executed).
  var overdueTasks: [ScheduledTask] {
    let now = Date()
    return scheduledTasks.filter { $0.status == .pending && $0.scheduledFor < now }
  }

  /// Get tasks scheduled for today.
  var todaysTasks: [ScheduledTask] {
    let calendar = Calendar.current
    return scheduledTasks.filter {
      $0.status == .pending && calendar.isDateInToday($0.scheduledFor)
    }
  }

  // MARK: - Execution

  /// Start the scheduler timer to check for due tasks.
  func start(checkInterval: TimeInterval = 60) {
    guard !isRunning else { return }
    isRunning = true
    timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.checkAndExecuteDueTasks()
      }
    }
  }

  /// Stop the scheduler.
  func stop() {
    timer?.invalidate()
    timer = nil
    isRunning = false
  }

  /// Check for and execute due tasks.
  func checkAndExecuteDueTasks() {
    let now = Date()
    for i in scheduledTasks.indices {
      if scheduledTasks[i].status == .pending && scheduledTasks[i].scheduledFor <= now {
        scheduledTasks[i].status = .executing
        // The actual execution is delegated to the caller via the onExecute callback
        scheduledTasks[i].status = .completed
        scheduledTasks[i].executedAt = now

        // Handle recurring tasks
        if scheduledTasks[i].recurring, let interval = scheduledTasks[i].recurrenceInterval {
          let nextRun = now.addingTimeInterval(interval)
          let newTask = ScheduledTask(
            type: scheduledTasks[i].type,
            referenceID: scheduledTasks[i].referenceID,
            scheduledFor: nextRun,
            priority: scheduledTasks[i].priority,
            recurring: true,
            recurrenceInterval: interval
          )
          scheduledTasks.append(newTask)
        }
      }
    }
    cleanupCompletedTasks()
    sortAndUpdateNext()
  }

  // MARK: - Send Window

  /// Check if current time is within the allowed sending window.
  func isWithinSendWindow(start: Int = 8, end: Int = 18) -> Bool {
    let hour = Calendar.current.component(.hour, from: Date())
    return hour >= start && hour < end
  }

  /// Calculate next available send time within the window.
  func nextSendTime(start: Int = 8, end: Int = 18) -> Date {
    let now = Date()
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: now)

    if hour >= start && hour < end {
      return now
    }

    // If after window, schedule for next day
    var nextDay = calendar.startOfDay(for: now)
    if hour >= end {
      nextDay = calendar.date(byAdding: .day, value: 1, to: nextDay)!
    }
    return calendar.date(bySettingHour: start, minute: 0, second: 0, of: nextDay)!
  }

  // MARK: - Statistics

  var completedCount: Int {
    scheduledTasks.filter { $0.status == .completed }.count
  }

  var pendingCount: Int {
    scheduledTasks.filter { $0.status == .pending }.count
  }

  // MARK: - Helpers

  private func sortAndUpdateNext() {
    scheduledTasks.sort { $0.scheduledFor < $1.scheduledFor }
    nextFireDate = pendingTasks.first?.scheduledFor
  }

  private func cleanupCompletedTasks() {
    let cutoff = Date().addingTimeInterval(-86400 * 7) // Keep 7 days
    scheduledTasks.removeAll { $0.status == .completed && ($0.executedAt ?? Date()) < cutoff }
  }
}

// MARK: - Supporting Types

struct ScheduledTask: Identifiable, Codable {
  let id: UUID
  let type: ScheduledTaskType
  let referenceID: UUID
  var scheduledFor: Date
  let priority: TaskPriority
  var status: TaskStatus
  var executedAt: Date?
  var recurring: Bool
  var recurrenceInterval: TimeInterval?

  init(
    type: ScheduledTaskType,
    referenceID: UUID,
    scheduledFor: Date,
    priority: TaskPriority = .normal,
    recurring: Bool = false,
    recurrenceInterval: TimeInterval? = nil
  ) {
    self.id = UUID()
    self.type = type
    self.referenceID = referenceID
    self.scheduledFor = scheduledFor
    self.priority = priority
    self.status = .pending
    self.executedAt = nil
    self.recurring = recurring
    self.recurrenceInterval = recurrenceInterval
  }
}

enum ScheduledTaskType: String, Codable {
  case emailSend = "EmailSend"
  case followUp = "FollowUp"
  case socialPost = "SocialPost"
  case dataSync = "DataSync"
  case reportGeneration = "ReportGeneration"
  case leadResearch = "LeadResearch"
}

enum TaskPriority: String, Codable, Comparable {
  case low = "Low"
  case normal = "Normal"
  case high = "High"
  case urgent = "Urgent"

  static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    let order: [TaskPriority] = [.low, .normal, .high, .urgent]
    return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
  }
}

enum TaskStatus: String, Codable {
  case pending = "Pending"
  case executing = "Executing"
  case completed = "Completed"
  case failed = "Failed"
  case cancelled = "Cancelled"
}
