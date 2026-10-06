import CoreGraphics
import Foundation
import ImageIO
import StudioKit
import UniformTypeIdentifiers

/// What Deck Beat can learn about a dropped file before it loads it.
enum SlideFiles {
    /// Presentation files macOS cannot draw: Keynote, PowerPoint, OpenDocument.
    static let presentationExtensions: Set<String> = ["key", "ppt", "pptx", "pps", "ppsx", "potx", "odp"]

    static func isPresentation(_ url: URL) -> Bool {
        presentationExtensions.contains(url.pathExtension.lowercased())
    }

    /// How to turn a presentation into slides Deck Beat reads.
    static func presentationAdvice(_ names: [String]) -> String {
        let which = names.count == 1 ? names[0] : "\(names.count) presentations"
        return "\(which) can’t be read directly. Export the deck as a PDF (in Keynote: File ▸ Export To ▸ PDF; "
            + "in PowerPoint: File ▸ Save As ▸ PDF; in Google Slides: File ▸ Download ▸ PDF) and drop the PDF here. "
            + "Each page becomes a slide."
    }

    /// The width over the height of an image or a PDF page as it will show, or
    /// nil when only loading it will tell (a movie).
    static func aspect(of url: URL, kind: MediaKind, page: Int) -> Float? {
        switch kind {
        case .image:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
            // Orientations 5…8 turn the picture a quarter.
            let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            return Float(orientation >= 5 ? h / w : w / h)
        case .pdfPage:
            guard let doc = CGPDFDocument(url as CFURL), let p = doc.page(at: page + 1) else { return nil }
            let box = p.getBoxRect(.cropBox)
            guard box.width > 0, box.height > 0 else { return nil }
            let turned = ((p.rotationAngle % 360) + 360) % 360 % 180 != 0
            return Float(turned ? box.height / box.width : box.width / box.height)
        case .video:
            return nil
        }
    }
}
