import Foundation

@MainActor final class HomelandComboLibraryStore:ObservableObject {
    @Published private(set) var library:HomelandComboLibrary?
    @Published private(set) var busy=false
    @Published private(set) var message:String?
    @Published private(set) var saved:HomelandComboSaveReceipt?
    @Published var name="My combo"
    private var descriptor:HomelandBuildTransactionDescriptor?
    private(set) var placed:HomelandBuildImportReceipt?
    var sharedCode:String? {guard let descriptor else{return nil};return HomelandBuildCodeCache().load(server:descriptor.server,number:descriptor.buildId)}
    var hasPlacedBuild:Bool {placed?.phase=="verified"}
    var canSave:Bool {
        guard let library,!busy,saved==nil else{return false}
        return hasPlacedBuild ? library.own.count<library.ownLimit && !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.utf8.count<=20 : sharedCode != nil && library.saved.count<library.savedLimit
    }
    func configure(_ descriptor:HomelandBuildTransactionDescriptor?) {
        guard self.descriptor != descriptor else{return}
        self.descriptor=descriptor;library=nil;placed=nil;saved=nil;message=nil
        guard let descriptor else{return}
        placed=try? HomelandBuildImportJournal(descriptor:descriptor).read()
        saved=try? HomelandComboSaveJournal(server:descriptor.server,build:descriptor.buildId).read()
        if let local=HomelandLocalBuildService().load().first(where:{$0.id=="\(descriptor.server.rawValue)-\(descriptor.buildId)"}){name=String(local.title.prefix(20))}
    }
    func refresh(connection:HomelandGameConnectionStore)async {
        guard !busy else{return};busy=true;defer{busy=false}
        do {
            try await connection.preparePurchaseConnection(currencyID:0,requireLibrary:true)
            library=try await connection.runBuildOperation{client,space in try await client.comboLibrary(expectedSpaceID:space)}
            message=nil
        }catch{message="The in-game combo library is unavailable. Keep Aniimo in your Homeland and try Refresh slots."}
    }
    func save(connection:HomelandGameConnectionStore)async {
        guard canSave,let descriptor else{return};let confirmedName=name.trimmingCharacters(in:.whitespacesAndNewlines);busy=true;defer{busy=false}
        let journal=HomelandComboSaveJournal(server:descriptor.server,build:descriptor.buildId)
        do {
            try await connection.preparePurchaseConnection(currencyID:0,requireLibrary:true)
            let fresh=try await connection.runBuildOperation{client,space in try await client.comboLibrary(expectedSpaceID:space)}
            library=fresh
            if hasPlacedBuild {guard fresh.own.count<fresh.ownLimit else{throw HomelandCommandClient.Failure.rejected}}
            else{guard fresh.saved.count<fresh.savedLimit else{throw HomelandCommandClient.Failure.rejected}}
            let receipt=hasPlacedBuild ? placed:nil;let code=sharedCode;let title=confirmedName
            saved=try await connection.runBuildOperation{client,space in try await client.saveBuildCombo(server:descriptor.server,build:descriptor.buildId,name:title,receipt:receipt,sharedCode:code,shareable:receipt != nil,expectedSpaceID:space,journal:journal)}
            message="Saved to Aniimo’s combo library. No furniture was moved or purchased."
            library=try? await connection.runBuildOperation{client,space in try await client.comboLibrary(expectedSpaceID:space)}
        }catch{
            saved=try? journal.read()
            message=saved==nil ? "The save was not sent. Refresh slots and check the build or code." : "Check saved combo before retrying. Atlas will not send this save again automatically."
        }
    }
    func recover(connection:HomelandGameConnectionStore)async {
        guard !busy,let descriptor else{return};busy=true;defer{busy=false}
        do{saved=try await connection.runBuildOperation{client,space in try await client.recoverComboSave(HomelandComboSaveJournal(server:descriptor.server,build:descriptor.buildId),expectedSpaceID:space)};message=saved?.phase=="complete" ? "Saved combo verified; nothing was saved again.":"The saved operation still needs review."}
        catch{message="The saved operation cannot be confirmed in this session. Nothing was sent again."}
    }
}
