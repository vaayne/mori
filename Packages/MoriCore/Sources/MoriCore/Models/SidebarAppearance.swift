import Foundation
import SwiftUI

public struct SidebarAppearance: Sendable, Equatable {
    public var fontFamily: String
    public var fontSize: CGFloat
    public var spacing: CGFloat

    public static let `default` = SidebarAppearance(
        fontFamily: "",
        fontSize: 14,
        spacing: 1.0
    )

    public init(fontFamily: String = "", fontSize: CGFloat = 14, spacing: CGFloat = 1.0) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.spacing = spacing
    }

    public func font(_ style: FontStyle) -> Font {
        let size = style.size(base: fontSize)
        let weight = style.weight
        let design = style.design
        if fontFamily.isEmpty {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(fontFamily, size: size).weight(weight)
    }

    public func scaled(_ value: CGFloat) -> CGFloat {
        (value * spacing).rounded()
    }

    public enum FontStyle: Sendable {
        case sectionTitle
        case rowTitle
        case windowTitle
        case label
        case caption
        case badgeCount
        case monoSmall
        case arrowIcon

        func size(base: CGFloat) -> CGFloat {
            switch self {
            case .sectionTitle: return base - 1
            case .rowTitle: return base + 1
            case .windowTitle: return base
            case .label: return base - 2
            case .caption: return base - 3
            case .badgeCount: return base - 5
            case .monoSmall: return base - 4
            case .arrowIcon: return base - 6
            }
        }

        var weight: Font.Weight {
            switch self {
            case .sectionTitle: return .semibold
            case .rowTitle: return .semibold
            case .windowTitle: return .regular
            case .label: return .regular
            case .caption: return .regular
            case .badgeCount: return .bold
            case .monoSmall: return .regular
            case .arrowIcon: return .regular
            }
        }

        var design: Font.Design {
            switch self {
            case .badgeCount: return .rounded
            case .monoSmall: return .monospaced
            case .arrowIcon: return .default
            default: return .default
            }
        }
    }
}

private enum SidebarAppearanceKey: EnvironmentKey {
    static let defaultValue = SidebarAppearance.default
}

public extension EnvironmentValues {
    var sidebarAppearance: SidebarAppearance {
        get { self[SidebarAppearanceKey.self] }
        set { self[SidebarAppearanceKey.self] = newValue }
    }
}

@Observable
public final class SidebarAppearanceStore: @unchecked Sendable {

    public var appearance: SidebarAppearance {
        didSet {
            guard appearance != oldValue else { return }
            save()
        }
    }

    private static let fontFamilyKey = "MoriSidebarFontFamily"
    private static let fontSizeKey = "MoriSidebarFontSize"
    private static let spacingKey = "MoriSidebarSpacing"

    public init() {
        let defaults = UserDefaults.standard
        let family = defaults.string(forKey: Self.fontFamilyKey) ?? ""
        let size = defaults.double(forKey: Self.fontSizeKey)
        let spacing = defaults.double(forKey: Self.spacingKey)
        self.appearance = SidebarAppearance(
            fontFamily: family,
            fontSize: size > 0 ? CGFloat(size) : SidebarAppearance.default.fontSize,
            spacing: spacing > 0 ? CGFloat(spacing) : SidebarAppearance.default.spacing
        )
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(appearance.fontFamily, forKey: Self.fontFamilyKey)
        defaults.set(Double(appearance.fontSize), forKey: Self.fontSizeKey)
        defaults.set(Double(appearance.spacing), forKey: Self.spacingKey)
    }
}
