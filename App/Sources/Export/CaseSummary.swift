import UIKit
import JawAtlasCore

struct SummaryMoment {
    let title: String
    let caption: String
    let image: UIImage

    init(title: String, caption: String, image: UIImage) {
        self.title = title
        self.caption = caption
        self.image = image
    }

    init(moment: StoryMoment, image: UIImage) {
        self.title = moment.title
        self.caption = moment.caption
        self.image = image
    }
}

@MainActor
struct CaseSummary {
    let caseLabel: String
    let moments: [SummaryMoment]
    let arPhoto: UIImage?
    let date: Date

    init(caseLabel: String, moments: [SummaryMoment], arPhoto: UIImage? = nil, date: Date = Date()) {
        self.caseLabel = caseLabel
        self.moments = moments
        self.arPhoto = arPhoto
        self.date = date
    }

    static let pageSize = CGSize(width: 595.2, height: 841.8)

    var headerText: String { "Case summary — \(caseLabel)" }

    var footerText: String {
        "Study summary exported from JawAtlas. "
            + "For education and training — not a diagnosis or treatment plan."
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var documentTitle: String { "\(caseLabel) — \(dateText)" }

    private enum PageContent {
        case moment(SummaryMoment)
        case photo(UIImage)
    }

    private var pages: [PageContent] {
        var result: [PageContent] = moments.map { .moment($0) }
        if let arPhoto {
            result.append(.photo(arPhoto))
        }
        return result
    }

    var pageCount: Int { pages.count }

    func pdfData() -> Data {
        let bounds = CGRect(origin: .zero, size: CaseSummary.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: documentTitle,
            kCGPDFContextCreator as String: "JawAtlas"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                draw(page, in: bounds)
            }
        }
    }

    func images() -> [UIImage] {
        let bounds = CGRect(origin: .zero, size: CaseSummary.pageSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return pages.map { page in
            renderer.image { context in
                UIColor.white.setFill()
                context.fill(bounds)
                draw(page, in: bounds)
            }
        }
    }

    private func draw(_ page: PageContent, in bounds: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)
        let margin: CGFloat = 44
        drawHeader(in: bounds, margin: margin)
        let footerTop = drawFooter(in: bounds, margin: margin)
        let contentTop: CGFloat = 96
        switch page {
        case let .moment(moment):
            drawMoment(moment, in: bounds, margin: margin, top: contentTop, bottom: footerTop - 12)
        case let .photo(photo):
            drawPhotoPage(photo, in: bounds, margin: margin, top: contentTop, bottom: footerTop - 12)
        }
    }

    private func drawHeader(in bounds: CGRect, margin: CGFloat) {
        let title = NSAttributedString(string: headerText, attributes: [
            .font: UIFont.systemFont(ofSize: 19, weight: .semibold),
            .foregroundColor: UIColor(white: 0.1, alpha: 1)
        ])
        title.draw(in: CGRect(x: margin, y: 36, width: bounds.width - margin * 2, height: 26))
        let dateLine = NSAttributedString(string: dateText, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ])
        dateLine.draw(in: CGRect(x: margin, y: 64, width: bounds.width - margin * 2, height: 16))
    }

    private func drawFooter(in bounds: CGRect, margin: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .center
        let footer = NSAttributedString(string: footerText, attributes: [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
            .paragraphStyle: paragraph
        ])
        let width = bounds.width - margin * 2
        let needed = footer.boundingRect(
            with: CGSize(width: width, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let top = bounds.height - 28 - ceil(needed.height)
        footer.draw(
            with: CGRect(x: margin, y: top, width: width, height: ceil(needed.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return top
    }

    private func drawMoment(
        _ moment: SummaryMoment,
        in bounds: CGRect,
        margin: CGFloat,
        top: CGFloat,
        bottom: CGFloat
    ) {
        let width = bounds.width - margin * 2
        let title = NSAttributedString(string: moment.title, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor(white: 0.12, alpha: 1)
        ])
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let caption = NSAttributedString(
            string: moment.caption.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor(white: 0.3, alpha: 1),
                .paragraphStyle: paragraph
            ]
        )
        let captionHeight = caption.string.isEmpty ? 0 : ceil(caption.boundingRect(
            with: CGSize(width: width, height: 140),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        let titleHeight: CGFloat = 22
        let textBlock = titleHeight + (captionHeight > 0 ? captionHeight + 6 : 0)
        let imageRect = fitted(
            imageSize: moment.image.size,
            into: CGRect(x: margin, y: top, width: width, height: max(bottom - top - textBlock - 14, 80))
        )
        moment.image.draw(in: imageRect)
        UIColor(white: 0.85, alpha: 1).setStroke()
        let border = UIBezierPath(rect: imageRect)
        border.lineWidth = 0.75
        border.stroke()
        var textY = imageRect.maxY + 12
        title.draw(in: CGRect(x: margin, y: textY, width: width, height: titleHeight))
        textY += titleHeight + 4
        if captionHeight > 0 {
            caption.draw(
                with: CGRect(x: margin, y: textY, width: width, height: captionHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private func drawPhotoPage(
        _ photo: UIImage,
        in bounds: CGRect,
        margin: CGFloat,
        top: CGFloat,
        bottom: CGFloat
    ) {
        let width = bounds.width - margin * 2
        let title = NSAttributedString(string: "On the table, life size", attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor(white: 0.12, alpha: 1)
        ])
        let caption = NSAttributedString(
            string: "A photo from the augmented reality view during your visit.",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor(white: 0.3, alpha: 1)
            ]
        )
        let textBlock: CGFloat = 22 + 18 + 6
        let imageRect = fitted(
            imageSize: photo.size,
            into: CGRect(x: margin, y: top, width: width, height: max(bottom - top - textBlock - 14, 80))
        )
        photo.draw(in: imageRect)
        title.draw(in: CGRect(x: margin, y: imageRect.maxY + 12, width: width, height: 22))
        caption.draw(in: CGRect(x: margin, y: imageRect.maxY + 38, width: width, height: 18))
    }

    private func fitted(imageSize: CGSize, into area: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return area }
        let scale = min(area.width / imageSize.width, area.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
