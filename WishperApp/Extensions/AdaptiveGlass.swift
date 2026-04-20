import SwiftUI

// MARK: - Adaptive Glass View Modifiers

/// Provides backward-compatible wrappers around macOS 26 Liquid Glass APIs,
/// falling back to `.ultraThinMaterial` backgrounds on macOS 14–15.

extension View {

    /// Applies `.glassEffect(.regular, in:)` on macOS 26+,
    /// falls back to `.background(.ultraThinMaterial, in:)` on earlier versions.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Applies `.glassEffect(.regular.interactive(), in:)` on macOS 26+,
    /// falls back to `.background(.ultraThinMaterial, in:)` on earlier versions.
    @ViewBuilder
    func adaptiveInteractiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Applies either interactive or regular glass based on a boolean flag.
    /// On macOS 26+ uses Liquid Glass; on earlier versions uses `.ultraThinMaterial`.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(interactive: Bool, in shape: S) -> some View {
        if interactive {
            self.adaptiveInteractiveGlass(in: shape)
        } else {
            self.adaptiveGlass(in: shape)
        }
    }

    /// Applies `.buttonStyle(.glassProminent)` on macOS 26+,
    /// falls back to `.buttonStyle(.borderedProminent)` on earlier versions.
    @ViewBuilder
    func adaptiveGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Applies `.buttonStyle(.glass)` on macOS 26+,
    /// falls back to `.buttonStyle(.bordered)` on earlier versions.
    @ViewBuilder
    func adaptiveGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
