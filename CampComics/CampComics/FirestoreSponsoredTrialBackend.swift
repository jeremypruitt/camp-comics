import Foundation
import FirebaseAuth
import FirebaseFirestore
import CampComicsCore

struct FirestoreSponsoredTrialBackend: SponsoredTrialBackend {
    static let collection = "sponsoredTrials"
    static let schemaVersion = 1

    private var docRef: DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection(Self.collection).document(uid)
    }

    func fetch() async throws -> SponsoredTrial {
        guard let docRef else { return .empty }
        let snapshot = try await docRef.getDocument()
        let ids = (snapshot.data()?["finalizedPlayerIds"] as? [String]) ?? []
        return SponsoredTrial(finalizedPlayerIds: Set(ids))
    }

    func recordFinalized(playerId: String) async throws {
        guard let docRef else { return }
        try await docRef.setData([
            "version": Self.schemaVersion,
            "finalizedPlayerIds": FieldValue.arrayUnion([playerId])
        ], merge: true)
    }
}
