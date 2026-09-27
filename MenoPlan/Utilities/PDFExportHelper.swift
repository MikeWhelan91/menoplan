import UIKit

enum PDFExportHelper {
    static func makeReport(scan: Scan, image: UIImage?) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "MenoPlan-\(scan.id.uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let title = "MenoPlan Result"
                title.draw(at: CGPoint(x: 44, y: 44), withAttributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold)])
                let lines = [
                    "Test type: \(scan.testType.title)",
                    "Date: \(DateFormatting.shortDate.string(from: scan.createdAt)) \(DateFormatting.shortTime.string(from: scan.createdAt))",
                    "Result: \(scan.resultType.title)",
                    "Analysis mode: \(scan.analysisMode.title)",
                    "Image readability: \(scan.certaintyPercentage)%",
                    scan.testType == .ovulation ? String(format: "Test/control photo value: %.2f", scan.testControlRatio) : nil,
                    scan.notes.isEmpty ? nil : "Notes: \(scan.notes)",
                    AppConstants.safetyCopy
                ].compactMap { $0 }
                var y: CGFloat = 96
                for line in lines {
                    let rect = CGRect(x: 44, y: y, width: 520, height: textHeight(for: line, width: 520))
                    line.draw(in: rect, withAttributes: bodyAttributes)
                    y += rect.height + 14
                }
                if let image {
                    let imageRect = aspectFitRect(for: image.size, in: CGRect(x: 44, y: y + 16, width: 320, height: 180))
                    image.draw(in: imageRect)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        return [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    private static func textHeight(for text: String, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttributes,
            context: nil
        )
        return ceil(bounds.height)
    }

    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
