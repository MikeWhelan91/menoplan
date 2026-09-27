import Foundation

@Observable
final class ResultViewModel {
    var notes = ""
    var selectedManualResult: ScanResultType = .unclear
}
