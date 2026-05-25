import Testing
import Foundation
@testable import CampComicsCore

@Suite("CaptureState")
struct CaptureStateMachineTests {

    private static let plan: [PanelRequirement] = [
        PanelRequirement(emotion: .neutral,  position: .front),
        PanelRequirement(emotion: .joy,      position: .front),
        PanelRequirement(emotion: .surprise, position: .front),
        PanelRequirement(emotion: .neutral,  position: .profile),
    ]

    @Test func initialStateHasNoCapturesAndIsNotReady() {
        let state = CaptureState(plan: Self.plan)

        #expect(state.isReadyToSubmit == false)
        #expect(state.capturedCount == 0)
        #expect(state.remainingCount == 4)
        #expect(state.remaining == Self.plan)
        for req in Self.plan {
            #expect(state.isCaptured(req) == false)
            #expect(state.capturedPhoto(for: req) == nil)
        }
    }

    @Test func recordingOneCaptureUpdatesCountsAndLookups() {
        var state = CaptureState(plan: Self.plan)
        let req = Self.plan[1]  // joy|front
        let photo = CapturedPhoto()

        state.record(photo, for: req)

        #expect(state.capturedCount == 1)
        #expect(state.remainingCount == 3)
        #expect(state.isCaptured(req) == true)
        #expect(state.capturedPhoto(for: req) == photo)
        #expect(state.isReadyToSubmit == false)
        #expect(state.remaining == [Self.plan[0], Self.plan[2], Self.plan[3]])
    }

    @Test func capturingEveryPlanRowFlipsReadyToSubmit() {
        var state = CaptureState(plan: Self.plan)
        for req in Self.plan {
            state.record(CapturedPhoto(), for: req)
        }

        #expect(state.isReadyToSubmit == true)
        #expect(state.capturedCount == 4)
        #expect(state.remainingCount == 0)
        #expect(state.remaining.isEmpty)
    }

    @Test func recordingForSameRequirementTwiceReplacesPreviousPhoto() {
        var state = CaptureState(plan: Self.plan)
        let req = Self.plan[0]
        let first = CapturedPhoto()
        let second = CapturedPhoto()

        state.record(first, for: req)
        state.record(second, for: req)

        #expect(state.capturedCount == 1)
        #expect(state.capturedPhoto(for: req) == second)
    }

    @Test func retakeOnCapturedRequirementClearsItAndReturnsThePhoto() {
        var state = CaptureState(plan: Self.plan)
        let req = Self.plan[0]
        let photo = CapturedPhoto()
        state.record(photo, for: req)

        let discarded = state.retake(req)

        #expect(discarded == photo)
        #expect(state.isCaptured(req) == false)
        #expect(state.capturedPhoto(for: req) == nil)
        #expect(state.capturedCount == 0)
    }

    @Test func retakeOnUncapturedRequirementIsANoOpAndReturnsNil() {
        var state = CaptureState(plan: Self.plan)
        let req = Self.plan[0]

        let discarded = state.retake(req)

        #expect(discarded == nil)
        #expect(state.capturedCount == 0)
    }

    @Test func retakeAfterReadyDropsItBackBelowReady() {
        var state = CaptureState(plan: Self.plan)
        for req in Self.plan {
            state.record(CapturedPhoto(), for: req)
        }
        #expect(state.isReadyToSubmit == true)

        state.retake(Self.plan[2])

        #expect(state.isReadyToSubmit == false)
        #expect(state.remainingCount == 1)
        #expect(state.remaining == [Self.plan[2]])
    }

    @Test func remainingPreservesOriginalPlanOrder() {
        var state = CaptureState(plan: Self.plan)
        // Capture out of order — the surviving rows should still be in plan order.
        state.record(CapturedPhoto(), for: Self.plan[2])
        state.record(CapturedPhoto(), for: Self.plan[0])

        #expect(state.remaining == [Self.plan[1], Self.plan[3]])
    }

    @Test func valueSemanticsLetUIDiffWithoutSurprise() {
        var a = CaptureState(plan: Self.plan)
        let b = a
        a.record(CapturedPhoto(), for: Self.plan[0])

        #expect(b.capturedCount == 0)
        #expect(a.capturedCount == 1)
        #expect(a != b)
    }
}
