import Foundation

/// The current client can return an untranslated numeric localisation key.
/// Counts remain live; a trusted indexed currency name is only a display label.
struct HomelandCurrencyLabel {
    static func resolve(_ value: HomelandCommandValue, itemID: Int64, cached: [String:String]) -> String? {
        if case .string(let name)=value,!name.isEmpty,name.utf8.count<=512 {return name}
        guard let key=value.integerID,key>0 else{return nil}
        if let name=cached[String(itemID)],!name.isEmpty,name.utf8.count<=512 {return name}
        // Same standard HUD labels used by HomelandResourceBalancesView.
        if itemID==1 {return "Glimmer"}
        if itemID==2 {return "Credits"}
        return "Item \(itemID)"
    }
}
