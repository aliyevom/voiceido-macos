import Foundation

enum FalBalance {
    struct Credits: Equatable {
        var amount: Double
        var currency: String
    }

    enum Snapshot: Equatable {
        case credits(Credits)
        case unauthorized
        case missingKey
        case unavailable
    }

    private static let endpoint = URL(string: "https://api.fal.ai/v1/account/billing?expand=credits")!

    static func fetch() async -> Snapshot {
        guard let key = FalKey.loadBilling() else { return .missingKey }
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { return .unauthorized }
            guard (200..<300).contains(status) else { return .unavailable }
            let decoded = try JSONDecoder().decode(BillingResponse.self, from: data)
            guard let credits = decoded.credits else { return .unavailable }
            return .credits(Credits(amount: credits.currentBalance, currency: credits.currency))
        } catch {
            return .unavailable
        }
    }

    static func title(for snapshot: Snapshot) -> String {
        switch snapshot {
        case .credits(let credits):
            return "fal.ai \(formatted(credits))"
        case .unauthorized:
            return "fal.ai balance needs a billing key"
        case .missingKey:
            return "fal.ai balance unavailable"
        case .unavailable:
            return "fal.ai balance unavailable"
        }
    }

    private static func formatted(_ credits: Credits) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = credits.currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: credits.amount)) ?? "\(credits.amount) \(credits.currency)"
    }
}

private struct BillingResponse: Decodable {
    var credits: CreditBalance?
}

private struct CreditBalance: Decodable {
    var currentBalance: Double
    var currency: String

    enum CodingKeys: String, CodingKey {
        case currentBalance = "current_balance"
        case currency
    }
}
