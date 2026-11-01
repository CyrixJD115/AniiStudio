import SwiftUI
import AppKit
import WebKit

struct HomelandBuildCodeView: View {
    let server: HomelandServer
    let number: Int
    @State private var code: String?
    @State private var showingAccess = false
    @State private var copied = false
    @State private var needsVerification = false
    @State private var accessError: String?
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Build code", systemImage: "number.square").font(.headline)
            if let code {
                HStack {
                    Text(code).font(.title3.weight(.semibold).monospaced()).textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                }
                Text("\(server.name) · revealed from the source").font(.caption).foregroundStyle(.secondary)
                Button("View saved code", systemImage: "number.square") { showingAccess = true }
            } else {
                Text("Reveal this layout's in-game combo code here in Atlas.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Reveal build code", systemImage: "eye") { needsVerification = false; accessError = nil; showingAccess = true }.buttonStyle(.bordered)
                Text("Aniidex may ask you to verify access inside the app.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(server.rawValue)-\(number)") {
            code = HomelandBuildCodeCache().load(server: server, number: number)
            copied = false
            saveError = nil
        }
        .sheet(isPresented: $showingAccess) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reveal build code").font(.title2.bold())
                        Text("\(server.name) · Build #\(number)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { showingAccess = false }.keyboardShortcut(.cancelAction)
                }
                if let code {
                    VStack(spacing: 18) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                        Text("Code revealed").font(.title.bold())
                        Text(code).font(.system(size: 36, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("\(server.name) · Build #\(number)")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(saveError ?? "Saved in Atlas").font(.caption).foregroundStyle(saveError == nil ? Color.secondary : .orange)
                        Button("Copy code", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            copied = true
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        if copied { Text("Copied to clipboard").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(needsVerification ? "The source requires an access check. Complete it below; your code will appear here and be saved automatically." : "Retrieving your build code…")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ZStack {
                    HomelandCodeAccessWeb(server: server, number: number, onVerification: { needsVerification = true }, onError: { accessError = $0 }) { revealed in
                        code = revealed
                        do { try HomelandBuildCodeCache().save(revealed, server: server, number: number); saveError = nil }
                        catch { saveError = "Code revealed, but saving failed. Copy it before closing." }
                    }.id("\(server.rawValue)-\(number)")
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(!needsVerification || accessError != nil)
                        .allowsHitTesting(needsVerification && accessError == nil)
                    if !needsVerification || accessError != nil {
                        VStack(spacing: 16) {
                            if accessError == nil { ProgressView().controlSize(.large) }
                            Text(accessError == nil ? "Revealing build code" : "Code unavailable").font(.headline)
                            if let accessError { Text(accessError).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                            Text("Codes you reveal are saved for instant offline access.").foregroundStyle(.secondary)
                            if accessError == nil { Button("Show access check") { needsVerification = true } }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).background { StudioBackdrop() }
                    }
                    }
                }

            }.padding(24).frame(width: 860, height: 650).background { StudioBackdrop() }
        }
    }
}

private struct HomelandCodeAccessWeb: NSViewRepresentable {
    let server: HomelandServer
    let number: Int
    let onVerification: () -> Void
    let onError: (String) -> Void
    let onCode: (String) -> Void
    private var url: URL { URL(string: "https://aniidex.com/homeland/layout-codes/\(server.rawValue)/\(number)/")! }
    func makeCoordinator() -> Coordinator { Coordinator(url: url, onCode: onCode, onVerification: onVerification, onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = config.userContentController
        controller.add(context.coordinator, name: "atlasBuildCode")
        let script = #"""
        (() => {
          const started = Date.now(); let attempts = 0; let lastClick = 0; let notified = false;
          function readCode() {
            const button = document.querySelector(".lc-ticket__stub button.ticket__copy");
            if (attempts < 3 && Date.now()-started > 1500 && Date.now()-lastClick > 2000 && button && !button.disabled && !document.querySelector(".lc-ticket.is-checking, iframe[src*=\"challenges.cloudflare.com\"]")) { attempts++; lastClick=Date.now(); button.click(); }
            const challenge = document.querySelector('iframe[src*="challenges.cloudflare.com"], .lc-ticket__error');
            if (!notified && (challenge || Date.now() - started > 12000)) { notified = true; window.webkit.messageHandlers.atlasBuildCode.postMessage("verification-required"); }
            const element = document.querySelector('code.lc-ticket__code');
            const value = element?.textContent?.trim();
            if (value && /^[A-Z0-9-]{6,32}$/.test(value))
              window.webkit.messageHandlers.atlasBuildCode.postMessage(value);
          }
          new MutationObserver(readCode).observe(document.documentElement, {subtree:true,childList:true,characterData:true});
          const timer = setInterval(readCode, 500);
          setTimeout(() => clearInterval(timer), 120000);
          readCode();
        })();
        """#
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        // Source access remains inside Atlas. Third-party advertising is not needed for code access.
        let rules = #"[{"trigger":{"url-filter":".*","if-domain":["*nitropay.com","*doubleclick.net","*googlesyndication.com"]},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "AtlasBuildCodeAds", encodedContentRuleList: rules) { list, _ in
            if let list { web.configuration.userContentController.add(list) }
            web.load(URLRequest(url: url))
        }
        return web
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "atlasBuildCode")
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let url: URL
        let onCode: (String) -> Void
        let onVerification: () -> Void
        let onError: (String) -> Void
        private var delivered = false
        init(url: URL, onCode: @escaping (String) -> Void, onVerification: @escaping () -> Void, onError: @escaping (String) -> Void) { self.url = url; self.onCode = onCode; self.onVerification = onVerification; self.onError = onError }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !delivered, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.host == url.host,
                  message.frameInfo.request.url?.path == url.path,
                  let code = message.body as? String else { return }
            if code == "verification-required" { onVerification(); return }
            guard HomelandBuildCodeCache.valid(code) else { return }
            delivered = true; onCode(code)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !delivered else { return }
            if webView.url?.path != url.path {
                onError("This build is no longer available from the source. Refresh the Build Library or choose another build.")
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !delivered { onError("The code could not load. Check your connection and try again.") }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError("The code could not load. Check your connection and try again.") }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.targetFrame?.isMainFrame == true,
               action.request.url?.host != "aniidex.com" { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}
