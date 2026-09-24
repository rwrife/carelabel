import Foundation
import Testing
@testable import CareKit

@Suite("Issue 1 product contract")
struct CareContractTests {
    @Test("Published care axes are the exact five from the plan")
    func careAxesMatchPublishedPlan() {
        #expect(CareAxis.allCases.map(\.rawValue) == [
            "wash", "bleach", "dry", "iron", "professionalCleaning",
        ])
        #expect(CareAxis.allCases.count == 5)
    }

    @Test("Layout seam resolves to compact today")
    func layoutSeamIsCompactToday() {
        #expect(CareWorkspaceLayout.current == .compact)
        #expect(Set(CareWorkspaceLayoutStyle.allCases.map(\.rawValue)) == ["compact", "regularWidth"])
    }

    @Test("Layout seam maps styles to the published presentations (issue #6)")
    func layoutPresentationSeam() {
        // Today's compact iPhone stacks picker and report sequentially.
        #expect(CareWorkspaceLayout.presentation() == .stacked)
        #expect(CareWorkspaceLayout.presentation(for: .compact) == .stacked)
        // Regular width — the documented dual-screen span target — is the
        // split picker|report mode. The seam is the ONLY way screens learn
        // this; no fold APIs exist here.
        #expect(CareWorkspaceLayout.presentation(for: .regularWidth) == .splitPanels)
        #expect(Set(CareWorkspacePresentation.allCases.map(\.rawValue)) == ["stacked", "splitPanels"])
    }

    @Test("Export forms are exactly the promised JSON archive and CSV summary")
    func exportFormsArePublishedSet() {
        #expect(CareExportFormat.allCases == [.jsonArchive, .csvSummary])
    }

    @Test("Photo downscale promise is a fixed positive dimension")
    func photoLimitIsSane() {
        #expect(CarePhotoLimits.maximumPhotoDimensionPoints > 0)
        #expect(CarePhotoLimits.maximumPhotoDimensionPoints == 1_600)
    }
}
