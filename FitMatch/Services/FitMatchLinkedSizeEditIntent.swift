import Foundation

/// A fresh-runtime option used only while editing a server-linked Closet row.
/// `ProductSize.id` is a presentation identity in many legacy paths, so the
/// UUID tuple travels beside it rather than being inferred from a label.
@MainActor
struct FitMatchLinkedClosetSizeEditOption: Identifiable {
    let displaySizeID: UUID
    let productSize: ProductSize
    let identity: FitMatchClosetRegistrationServerIdentity

    var id: UUID { displaySizeID }
}

@MainActor
struct FitMatchLinkedClosetSizeEditPreparation {
    let userID: UUID
    let clientItemID: UUID
    let currentServerIdentity: FitMatchClosetRegistrationServerIdentity
    let options: [FitMatchLinkedClosetSizeEditOption]
    let initialDisplaySizeID: UUID

    func option(displaySizeID: UUID) -> FitMatchLinkedClosetSizeEditOption? {
        options.first { $0.displaySizeID == displaySizeID }
    }

    func intent(
        for selectedDisplaySizeID: UUID,
        localUpdatedAt: Date
    ) -> FitMatchLinkedSizeEditIntent? {
        guard let option = option(displaySizeID: selectedDisplaySizeID),
              option.identity != currentServerIdentity else {
            return nil
        }
        return FitMatchLinkedSizeEditIntent(
            token: UUID(),
            userID: userID,
            clientItemID: clientItemID,
            selectedDisplaySizeID: option.displaySizeID,
            productID: option.identity.productID,
            variantID: option.identity.productVariantID,
            productSizeID: option.identity.productSizeID,
            localUpdatedAt: localUpdatedAt
        )
    }
}

enum FitMatchLinkedClosetSizeEditPreparationError: LocalizedError {
    case authenticationChanged
    case currentClosetRowUnavailable
    case missingRetailerFacts
    case runtimeIdentityUnavailable

    var errorDescription: String? {
        switch self {
        case .authenticationChanged:
            return "로그인 상태가 변경되어 최신 사이즈 정보를 확인할 수 없습니다."
        case .currentClosetRowUnavailable:
            return "서버의 현재 옷장 정보를 확인하지 못했습니다. 새로고침 후 다시 시도해 주세요."
        case .missingRetailerFacts:
            return "이 옷의 쇼핑몰 상품 정보를 확인할 수 없어 사이즈를 안전하게 변경할 수 없습니다."
        case .runtimeIdentityUnavailable:
            return "서버의 최신 사이즈 정보를 확인하지 못했습니다. 새로고침 후 다시 시도해 주세요."
        }
    }
}

/// A user-confirmed size change for an already linked Closet row.  This is a
/// user-scoped journal, not product identity storage: the exact identifiers
/// are obtained from a fresh runtime preparation immediately before the edit.
/// It survives logout for the same account so account-local sync can finish,
/// but another account can never read its namespace.
nonisolated struct FitMatchLinkedSizeEditIntent: Codable, Equatable, Sendable {
    let token: UUID
    let userID: UUID
    let clientItemID: UUID
    let selectedDisplaySizeID: UUID
    let productID: UUID
    let variantID: UUID
    let productSizeID: UUID
    let localUpdatedAt: Date

    func matchesServer(
        productID: UUID?,
        variantID: UUID?,
        productSizeID: UUID?
    ) -> Bool {
        self.productID == productID
            && self.variantID == variantID
            && self.productSizeID == productSizeID
    }
}

enum FitMatchLinkedSizeEditIntentStore {
    private static let keyPrefix = "FitMatch.pendingLinkedSizeEdit.v1."

    static func intent(
        userID: UUID,
        clientItemID: UUID,
        defaults: UserDefaults
    ) -> FitMatchLinkedSizeEditIntent? {
        let key = key(userID: userID, clientItemID: clientItemID)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FitMatchLinkedSizeEditIntent.self, from: data)
    }

    static func store(
        _ intent: FitMatchLinkedSizeEditIntent,
        defaults: UserDefaults
    ) {
        let key = key(userID: intent.userID, clientItemID: intent.clientItemID)
        guard let data = try? JSONEncoder().encode(intent) else { return }
        defaults.set(data, forKey: key)
    }

    static func remove(
        userID: UUID,
        clientItemID: UUID,
        defaults: UserDefaults,
        onlyIfTokenMatches token: UUID? = nil
    ) {
        if let token,
           intent(userID: userID, clientItemID: clientItemID, defaults: defaults)?.token != token {
            return
        }
        defaults.removeObject(forKey: key(userID: userID, clientItemID: clientItemID))
    }

    static func purge(userID: UUID, defaults: UserDefaults) {
        let prefix = keyPrefix + userID.uuidString + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(userID: UUID, clientItemID: UUID) -> String {
        keyPrefix + userID.uuidString + "." + clientItemID.uuidString
    }
}
