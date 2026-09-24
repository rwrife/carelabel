import Foundation

/// Stable product contracts shared by the app and the future domain implementation.
/// These mirror the published MVP plan (PLAN.md / README.md); later milestones own
/// enforcement: the full `CareProfile` value types and ISO 3758 symbol table are
/// issue #2, the compatibility engine is issue #3, and persistence (including the
/// photo downscale below) is issue #4.

/// The five care axes every care profile records, exactly as published in PLAN.md:
/// wash (temperature/action), bleach, dry (method/heat), iron (cap), and
/// professional cleaning. Explicit "do not" prohibitions attach to these axes;
/// they are not a sixth axis.
public enum CareAxis: String, CaseIterable, Sendable {
    case wash
    case bleach
    case dry
    case iron
    case professionalCleaning
}

/// The single layout-adaptation seam promised by the PLAN: every layout decision
/// routes through `CareWorkspaceLayout`. Today it resolves to the standard compact
/// iPhone layout; regular-width (and the documented iPhone Duo dual-screen design
/// target) only ever become real through this seam — never through direct
/// dependence on unavailable fold APIs.
public enum CareWorkspaceLayoutStyle: String, CaseIterable, Sendable {
    case compact
    case regularWidth
}

/// What a workspace screen should render for a resolved layout style
/// (issue #6). `stacked` is today's iPhone behavior: picker and report are
/// sequential screens/sections. `splitPanels` is the documented iPhone Duo
/// design target realized early: the garment picker occupies one surface
/// and the live compatibility report the other — when fold APIs ship, the
/// split panels span the two screens with no call-site changes.
public enum CareWorkspacePresentation: String, CaseIterable, Sendable {
    case stacked
    case splitPanels
}

public enum CareWorkspaceLayout {
    /// The style the iPhone-only MVP resolves to. Changing dual-screen behavior
    /// later must only change this resolution, not call sites.
    public static let current: CareWorkspaceLayoutStyle = .compact

    /// The single resolution seam (issue #6): screens never choose stacked
    /// vs split layout themselves — they ask this. Compact (today's iPhone
    /// in every orientation the MVP ships) resolves to `stacked`; the
    /// regular-width style reserved for larger iPhone sizes and the future
    /// dual-screen span resolves to `splitPanels`.
    public static func presentation(
        for style: CareWorkspaceLayoutStyle = current
    ) -> CareWorkspacePresentation {
        switch style {
        case .compact: .stacked
        case .regularWidth: .splitPanels
        }
    }
}

/// The user-initiated export forms promised by the README (backup/restore JSON
/// archive and CSV garment summary); issue #6 owns the implementation.
public enum CareExportFormat: String, CaseIterable, Sendable {
    case jsonArchive
    case csvSummary
}

/// Photo-import downscale promise. Imported label photos are downscaled so their
/// longest edge is at most this many points, and originals are not retained
/// (issue #4 enforces this at the storage boundary).
public enum CarePhotoLimits {
    public static let maximumPhotoDimensionPoints: Int = 1_600
}
