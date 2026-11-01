import SwiftUI
struct ProductionMutationView: View {
    let formulaID: String
    var body: some View {
        if let mutations = InstalledProductionMutations.current.byFormula[formulaID], !mutations.isEmpty {
            DisclosureGroup("Mutation outputs · \(mutations.count) variants") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configured variants, not guaranteed harvests. Effective chances depend on additional conditions and modifiers; no expected sale profit is calculated.").font(.caption).foregroundStyle(.secondary)
                    ForEach(mutations) { mutation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mutation.name).font(.callout.bold())
                            if let quantity = mutation.quantity { Text("Listed output quantity: \(quantity.formatted())").font(.caption) }
                            if let price = mutation.baseSalePrice, let currency = mutation.currencyName { Text("Base sale price: \(price.formatted()) \(currency) each").font(.caption) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        }
    }
}
