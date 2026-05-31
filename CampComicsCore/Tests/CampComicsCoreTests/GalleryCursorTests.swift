import Foundation
import Testing
@testable import CampComicsCore

@Suite("GalleryCursor (slice E)")
struct GalleryCursorTests {

    @Test func emptyGalleryReportsZeroOfZero() {
        let c = GalleryCursor(index: 0, count: 0)
        #expect(c.isEmpty)
        #expect(c.positionLabel == "0 of 0")
    }

    @Test func positionLabelIsOneIndexed() {
        let c = GalleryCursor(index: 0, count: 3)
        #expect(c.positionLabel == "1 of 3")
    }

    @Test func advancedWalksForwardThroughGallery() {
        var c = GalleryCursor(index: 0, count: 3)
        c = c.advanced(); #expect(c.positionLabel == "2 of 3")
        c = c.advanced(); #expect(c.positionLabel == "3 of 3")
    }

    @Test func advancedWrapsFromLastToFirst() {
        let c = GalleryCursor(index: 2, count: 3).advanced()
        #expect(c.index == 0)
        #expect(c.positionLabel == "1 of 3")
    }

    @Test func retreatedWalksBackwardThroughGallery() {
        var c = GalleryCursor(index: 2, count: 3)
        c = c.retreated(); #expect(c.positionLabel == "2 of 3")
        c = c.retreated(); #expect(c.positionLabel == "1 of 3")
    }

    @Test func retreatedWrapsFromFirstToLast() {
        let c = GalleryCursor(index: 0, count: 3).retreated()
        #expect(c.index == 2)
        #expect(c.positionLabel == "3 of 3")
    }

    @Test func twoCandidateGalleryIsSymmetricUnderUpAndDown() {
        // ADR-0009 ergonomics: with 2 candidates, swipe-up and swipe-down land
        // on the same other candidate. Wrapping (not clamping) gives that.
        let a = GalleryCursor(index: 0, count: 2)
        #expect(a.advanced().index == 1)
        #expect(a.retreated().index == 1)
    }

    @Test func singleCandidateGalleryCannotMove() {
        let c = GalleryCursor(index: 0, count: 1)
        #expect(c.advanced() == c)
        #expect(c.retreated() == c)
    }

    @Test func afterAppendJumpsToNewest() {
        // Re-roll lands the new candidate at index `count - 1` and the visible
        // cursor follows it ("newest on top" per ADR-0009).
        #expect(GalleryCursor.afterAppend(count: 1).index == 0)
        #expect(GalleryCursor.afterAppend(count: 3).index == 2)
        #expect(GalleryCursor.afterAppend(count: 5).positionLabel == "5 of 5")
    }

    @Test func forNewHeadStartsAtFirstCandidate() {
        #expect(GalleryCursor.forNewHead(count: 0).isEmpty)
        #expect(GalleryCursor.forNewHead(count: 4).index == 0)
        #expect(GalleryCursor.forNewHead(count: 4).positionLabel == "1 of 4")
    }

    @Test func initNormalisesOutOfRangeIndex() {
        // Defensive: a saved-then-stale cursor (count shrank under us) should
        // wrap to a legal index rather than crash.
        let high = GalleryCursor(index: 99, count: 4)
        #expect(high.index == 3)   // 99 % 4 == 3
        let negative = GalleryCursor(index: -1, count: 4)
        #expect(negative.index == 3)   // ((-1 % 4) + 4) % 4 == 3
    }
}
