import SwiftUI
import WebKit

struct WebPanel: View {
    let url: URL
    @StateObject private var state = WebLoadState()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { state.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!state.canGoBack).help("Back")
                Button { state.webView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!state.canGoForward).help("Forward")
                Button { state.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload page")
                Text((state.currentURL ?? url).host ?? "Web resource").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Link("Open in browser", destination: state.currentURL ?? url).font(.caption)
            }.buttonStyle(.borderless).padding(10)
            Divider()
            ZStack {
                EmbeddedWeb(url: url, state: state)
                if let error = state.error {
                    ContentUnavailableView { Label("Page unavailable", systemImage: "wifi.exclamationmark") } description: { Text(error) } actions: {
                        Button("Retry") { state.error = nil; state.webView?.load(URLRequest(url: state.currentURL ?? url)) }
                        Link("Open in browser", destination: state.currentURL ?? url)
                    }.padding().background(.regularMaterial)
                } else if state.loading {
                    ProgressView("Loading live resource…").padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
@MainActor final class WebLoadState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?
    func update(_ view: WKWebView) {
        currentURL = view.url
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
    }
}
private struct EmbeddedWeb: NSViewRepresentable {
    let url: URL
    @ObservedObject var state: WebLoadState
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        state.webView = view
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            view.load(URLRequest(url: url))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: url, state: state) }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var url: URL
        let state: WebLoadState
        init(url: URL, state: WebLoadState) { self.url = url; self.state = state }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.loading = true; state.error = nil; state.update(webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { state.update(webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.loading = false; state.update(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { state.error = error.localizedDescription; state.loading = false } }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            return nil
        }
    }
}
