import Foundation
import SwiftData

/// One AI-generated recap of the last 7 days of activity - scans, cycle/body-sign logs, and
/// symptoms - with a couple of grounded observations and next steps. Generated automatically
/// (see WeeklyLunaUpdateService), never by the user tapping a button, so this only ever grows
/// by one record roughly once a week.
@Model
final class WeeklyLunaUpdate {
    var id: UUID = UUID()
    var weekStartDate: Date = Date.now
    var weekEndDate: Date = Date.now
    var reply: String = ""
    var createdAt: Date = Date.now
    var isRead: Bool = false

    init(id: UUID = UUID(), weekStartDate: Date, weekEndDate: Date, reply: String) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.reply = reply
        self.createdAt = .now
        self.isRead = false
    }
}
