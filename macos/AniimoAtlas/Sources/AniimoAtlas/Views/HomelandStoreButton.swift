import SwiftUI

struct HomelandStoreButton:View {
 let instances:[Int64:Int64]
 @ObservedObject var connection:HomelandGameConnectionStore
 var title="Store in inventory"
 @State private var confirming=false
 @State private var busy=false
 @State private var message:String?
 var body:some View {
  VStack(alignment:.leading,spacing:6){
   Button(title,systemImage:"shippingbox.and.arrow.backward"){confirming=true}
    .disabled(busy || !connection.connected || instances.isEmpty || connection.isReadingResources || connection.isPurchasing)
   if let message{Text(message).font(.caption).foregroundStyle(.secondary)}
  }
  .confirmationDialog("Store \(instances.count) placed pieces in inventory?",isPresented:$confirming,titleVisibility:.visible){
   Button("Store pieces"){Task{await store()}}
   Button("Cancel",role:.cancel){}
  }message:{Text("Returns only these exact pieces to inventory. Other furniture is preserved. Multi-Select is handled automatically.")}
 }
 @MainActor private func store() async {
  guard !busy else{return};busy=true;defer{busy=false}
  do{
   try await connection.preparePurchaseConnection(currencyID:0,requireStorage:true)
   let count=try await connection.runBuildOperation{client,space in
    let sources=try await client.storageSources(instances,expectedSpaceID:space)
    let receipt=try await client.storeFacilities(sources,expectedSpaceID:space)
    return receipt.sources.count
   }
   message="\(count) pieces returned to inventory and verified. Refresh the map to see the opening."
  }catch{message="Storage did not reach a verified result. No automatic retry was sent; review the saved storage record before trying again."}
 }
}
