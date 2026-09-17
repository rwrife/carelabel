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
