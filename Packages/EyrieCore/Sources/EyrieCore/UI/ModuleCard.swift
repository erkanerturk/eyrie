import SwiftUI

/// Shared Liquid Glass card used for every module's section in the menu bar
/// panel. Keeps the visual language consistent across modules.
public struct ModuleCard<Content: View, Accessory: View>: View {
    private let title: String
    private let symbolName: String
    private let isActive: Bool
    private let content: Content
    private let accessory: Accessory

    public init(
        title: String,
        symbolName: String,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.symbolName = symbolName
        self.isActive = isActive
        self.content = content()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                accessory
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Compact glass capsule button used for secondary actions inside cards.
public struct GlassIconButton: View {
    /// Standard control size, and a smaller variant for buttons that sit on a
    /// caption-height text row — at 22 pt the button, not the text, sets the
    /// row height and the surrounding stack spacing reads as a gap.
    public enum Size {
        case regular
        case compact

        var side: CGFloat { self == .regular ? 22 : 18 }
        var symbolSize: CGFloat { self == .regular ? 12 : 10 }
    }

    private let symbolName: String
    private let size: Size
    private let action: () -> Void

    public init(symbolName: String, size: Size = .regular, action: @escaping () -> Void) {
        self.symbolName = symbolName
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: size.symbolSize, weight: .semibold))
                .frame(width: size.side, height: size.side)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
