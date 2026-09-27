import Foundation
import TipKit

struct FirstScanTip: Tip { var title: Text { Text("Start with a clear test photo") }; var message: Text? { Text("Use even lighting and keep the test inside the frame.") } }
struct AIQuickCheckTip: Tip { var title: Text { Text("Luna Check") }; var message: Text? { Text("MenoPlan auto-enhances the image and reports how readable the photo is.") } }
struct ManualEnhanceTip: Tip { var title: Text { Text("Check the photo yourself") }; var message: Text? { Text("Try contrast, greyscale, or invert to make faint lines easier to see.") } }
struct CertaintyTip: Tip { var title: Text { Text("Image readability") }; var message: Text? { Text("Image readability reflects how clearly the app could compare the visible lines in the photo. It is not medical certainty.") } }
struct TCRatioTip: Tip { var title: Text { Text("Test and control line comparison") }; var message: Text? { Text("This photo value compares the test line with the control line. It is guidance, not a hormone measurement.") } }

enum TipService {
    static func configure() {
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
    }
}
