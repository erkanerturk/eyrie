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
    private let symbolName: String
    private let action: () -> Void

    public init(symbolName: String, action: @escaping () -> Void) {
        self.symbolName = symbolName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
