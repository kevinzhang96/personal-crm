// Tend's visual identity — "midnight glass", copied from tcgdb: a deep
// navy (or in light mode, cool paper) gradient ground, glass floating
// controls, and semantic accents. Here blue = action, green = in touch /
// on track, orange = overdue / due. An accent is never decoration.

import SwiftUI
import UIKit

private func adaptive(dark: UIColor, light: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

enum Theme {
    static let bgTop = adaptive(
        dark: UIColor(red: 0.051, green: 0.059, blue: 0.086, alpha: 1),    // #0D0F16
        light: UIColor(red: 0.957, green: 0.961, blue: 0.973, alpha: 1))   // #F4F5F8
    static let bgBottom = adaptive(
        dark: UIColor(red: 0.094, green: 0.125, blue: 0.188, alpha: 1),    // #182030
        light: UIColor(red: 0.882, green: 0.906, blue: 0.945, alpha: 1))   // #E1E7F1
    static let panelFill = adaptive(
        dark: UIColor(white: 1, alpha: 0.055), light: UIColor(white: 0, alpha: 0.045))
    static let panelStroke = adaptive(
        dark: UIColor(white: 1, alpha: 0.08), light: UIColor(white: 0, alpha: 0.07))
    static let accent = Color(red: 0.208, green: 0.522, blue: 0.886)       // #3585E2
    static let rise = Color(red: 0.106, green: 0.686, blue: 0.478)         // #1BAF7A
    static let warn = Color(red: 0.914, green: 0.541, blue: 0.231)         // #E98A3B

    static var background: some View {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    /// The colour a status carries everywhere it is shown.
    static func tint(for status: ContactStatus) -> Color {
        switch status {
        case .overdue: warn
        case .dueSoon: warn.opacity(0.8)
        case .onTrack: rise
        case .snoozed, .never: Color.secondary
        }
    }
}

/// The user's appearance choice, applied at the root. "system" defers.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panelFill, in: .rect(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(Panel()) }

    /// A List row that gets out of the way — no separator, no chrome —
    /// so the panel inside it is the only thing the reader sees.
    func plainRow(
        _ insets: EdgeInsets = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    ) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
    }
}

/// The app's glass capsule: a circle filter, an entry kind, a choice.
/// Tinted when it is the active choice, plain glass otherwise.
struct GlassChip<Label: View>: View {
    var active = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(active ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                     in: .capsule)
    }
}

/// A horizontal strip of glass chips. The glass container wraps the
/// scroll view rather than sitting inside it: glass inside a scroll view
/// paints its own backdrop as a band across the row.
struct ChipStrip<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) { content }
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// A floating glass circle — the 2–3 global actions of a screen, placed
/// by overlay so they survive search-bar collapse.
struct GlassCircle: View {
    let icon: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(), in: .circle)
    }
}

/// Every screen that is a column of panels: the gradient ground, one
/// scroll view, and the panels down it at the app's spacing and insets.
struct PanelScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
            }
        }
    }
}

/// A status word beside a name — tinted text on its own wash, never a
/// shouting filled capsule: status is context, not the point of the row.
struct Badge: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .kerning(0.4)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Emptiness explains: what this screen will hold, and what to do next.
struct EmptyPanel: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Text(hint).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .panel()
    }
}
