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

public enum CareWorkspaceLayout {
    /// The style the iPhone-only MVP resolves to. Changing dual-screen behavior
    /// later must only change this resolution, not call sites.
    public static let current: CareWorkspaceLayoutStyle = .compact
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
