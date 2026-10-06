import AppKit
import CoreText
import SwiftUI

/// Interface text roles, set in the system font so the apps read as native
/// Mac apps: sizes follow the macOS inspector scale, numbers use tabular
/// figures, and nothing depends on bundled fonts.
public enum TextRole: String, CaseIterable, Sendable {
    case display, pageTitle, sectionTitle, panelTitle, body, bodyCompact, label, action, input, caption, badge, metadata, data, code
}

public struct TextRoleSpec: Sendable {
    public var size: CGFloat
    public var weight: Font.Weight
    public var design: Font.Design = .default
    public var tracking: CGFloat = 0  // in points
    public var uppercase = false
    public var monospacedDigits = false
}

public enum StudioType {
    /// Reported by headless runs, so a check can see which type the interface uses.
    public static var status: String { "system type, \(TextRole.allCases.count) roles, \(ReelTitle.Face.allCases.count) title faces, \(PDType.status)" }

    public static func spec(_ role: TextRole) -> TextRoleSpec {
        switch role {
        case .display: return TextRoleSpec(size: 26, weight: .semibold, tracking: -0.4)
        case .pageTitle: return TextRoleSpec(size: 20, weight: .semibold, tracking: -0.2)
        case .sectionTitle: return TextRoleSpec(size: 15, weight: .semibold)
        case .panelTitle: return TextRoleSpec(size: 17, weight: .semibold, tracking: -0.2)
        case .body: return TextRoleSpec(size: 13, weight: .regular)
        case .bodyCompact: return TextRoleSpec(size: 12, weight: .regular)
        case .label: return TextRoleSpec(size: 12, weight: .semibold)
        case .action: return TextRoleSpec(size: 13, weight: .medium)
        case .input: return TextRoleSpec(size: 13, weight: .regular)
        case .caption: return TextRoleSpec(size: 11.5, weight: .regular)
        case .badge: return TextRoleSpec(size: 9.5, weight: .semibold, tracking: 0.4, uppercase: true)
        case .metadata: return TextRoleSpec(size: 11, weight: .regular)
        case .data: return TextRoleSpec(size: 11.5, weight: .medium, monospacedDigits: true)
        case .code: return TextRoleSpec(size: 11, weight: .regular, design: .monospaced)
        }
    }

    public static func font(_ role: TextRole, size: CGFloat? = nil) -> Font {
        let s = spec(role)
        let f = Font.system(size: size ?? s.size, weight: s.weight, design: s.design)
        return s.monospacedDigits ? f.monospacedDigit() : f
    }

    public static func nsFont(_ role: TextRole, size: CGFloat? = nil) -> NSFont {
        let s = spec(role)
        let weight: NSFont.Weight
        switch s.weight {
        case .semibold: weight = .semibold
        case .medium: weight = .medium
        case .bold: weight = .bold
        default: weight = .regular
        }
        return s.design == .monospaced
            ? NSFont.monospacedSystemFont(ofSize: size ?? s.size, weight: weight)
            : NSFont.systemFont(ofSize: size ?? s.size, weight: weight)
    }
}

public struct StudioTextStyle: ViewModifier {
    let role: TextRole
    let size: CGFloat?

    public func body(content: Content) -> some View {
        let s = StudioType.spec(role)
        return content
            .font(StudioType.font(role, size: size))
            .tracking(s.tracking)
            .textCase(s.uppercase ? .uppercase : nil)
    }
}

extension View {
    /// Applies an interface text role.
    public func textStyle(_ role: TextRole, size: CGFloat? = nil) -> some View {
        modifier(StudioTextStyle(role: role, size: size))
    }
}

// MARK: - Faces for words set into the picture

public enum Faces {
    /// A face by PostScript name, falling back to a licensed sans if missing.
    public static func font(_ name: String, size: CGFloat) -> CTFont {
        let f = CTFontCreateWithName(name as CFString, size, nil)
        let got = CTFontCopyPostScriptName(f) as String
        if got == name { return f }
        return CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
    }

    /// Avenir Next at a weight, for sample slides and other rendered content.
    public static func avenir(_ size: CGFloat, _ weight: Double = 400) -> CTFont {
        let name: String
        switch weight {
        case ..<450: name = "AvenirNext-Regular"
        case ..<550: name = "AvenirNext-Medium"
        case ..<650: name = "AvenirNext-DemiBold"
        case ..<750: name = "AvenirNext-Bold"
        default: name = "AvenirNext-Heavy"
        }
        return font(name, size: size)
    }
}

/// pitch.dog's own type, bundled with the app from the pitch.dog type system:
/// PD Head and PD Eyebrow, variable fonts set at the system's anchor weights.
/// The fonts load straight from their files, so a copy the user has installed
/// is never doubled up.
public enum PDType {
    static let wght: UInt32 = 0x7767_6874, ital: UInt32 = 0x6974_616C, wdth: UInt32 = 0x7764_7468

    /// The fonts' descriptors, read once from Resources/Fonts.
    nonisolated(unsafe) private static let faces: (head: CTFontDescriptor?, eyebrow: CTFontDescriptor?) = {
        func load(_ file: String) -> CTFontDescriptor? {
            guard let url = StudioResources.url("Fonts/" + file),
                  let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
            return all.first
        }
        return (load("pd-head.ttf"), load("pd-eyebrow-full.ttf"))
    }()

    /// Which faces loaded, for headless runs and checks.
    public static var status: String {
        let found = [faces.head.map { _ in "PD Head" }, faces.eyebrow.map { _ in "PD Eyebrow" }].compactMap { $0 }
        return found.isEmpty ? "pitch.dog fonts missing, falling back to Avenir Next" : found.joined(separator: " and ") + " loaded"
    }

    /// PD Head at `size`: 600 is the system's display anchor. No weight between anchors.
    public static func head(_ size: CGFloat, weight: CGFloat = 600, italic: Bool = false) -> CTFont? {
        guard let d = faces.head else { return nil }
        let anchors: [CGFloat] = [265, 300, 400, 500, 600, 700, 900]
        let w = anchors.min { abs($0 - weight) < abs($1 - weight) } ?? 600
        return font(d, size, [wght: w, ital: italic ? 1 : 0])
    }

    /// PD Eyebrow at `size`: 500 at the narrow width, the system's metadata role.
    public static func eyebrow(_ size: CGFloat, weight: CGFloat = 500, width: CGFloat = 87.5) -> CTFont? {
        guard let d = faces.eyebrow else { return nil }
        return font(d, size, [wght: weight, wdth: width, ital: 0])
    }

    static func font(_ d: CTFontDescriptor, _ size: CGFloat, _ axes: [UInt32: CGFloat]) -> CTFont {
        var desc = d
        for (tag, value) in axes { desc = CTFontDescriptorCreateCopyWithVariation(desc, tag as CFNumber, value) }
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }
}

/// Finds bundled resources in an app bundle, or in the source tree during development.
public enum StudioResources {
    nonisolated(unsafe) private static var cache: [String: URL] = [:]

    public static func url(_ name: String) -> URL? {
        if let c = cache[name] { return c }
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent(name), fm.fileExists(atPath: r.path) {
            cache[name] = r
            return r
        }
        if let env = ProcessInfo.processInfo.environment["STUDIO_RESOURCES"] {
            let r = URL(fileURLWithPath: env).appendingPathComponent(name)
            if fm.fileExists(atPath: r.path) { cache[name] = r; return r }
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("Resources").appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { cache[name] = candidate; return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
