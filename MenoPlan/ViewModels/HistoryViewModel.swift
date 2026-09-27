import Foundation

@Observable
final class HistoryViewModel {
    var searchText = ""
    var filter: HistoryFilter = .ovulation
}
