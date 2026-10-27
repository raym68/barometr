import CoreMotion
import SwiftUI
import WebKit

struct BarrometrWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "barrometrStore")

        let saved = UserDefaults.standard.string(forKey: "barrometr-site-state") ?? "{}"
        let encodedState = String(
            data: (try? JSONEncoder().encode(saved)) ?? Data("\"{}\"".utf8),
            encoding: .utf8
        ) ?? "\"{}\""
        let bootstrap = """
        window.BarrometrNativeApp = true;
        window.BarrometrNativeInitialState = JSON.parse(\(encodedState));
        """
        contentController.addUserScript(WKUserScript(
            source: bootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let page = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<p>Страница сайта не включена в приложение.</p>", baseURL: nil)
        }
        context.coordinator.startBarometer()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopBarometer()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "barrometrStore")
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let altimeter = CMAltimeter()
        private var readings: [Double] = []
        private var lastError: String?

        func startBarometer() {
            guard CMAltimeter.isRelativeAltitudeAvailable() else {
                sendError("На этом iPhone барометр недоступен. Можно ввести давление вручную.")
                return
            }

            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.sendError("Нет доступа к барометру: \(error.localizedDescription)")
                    return
                }
                guard let data else { return }
                // Apple reports CMAltitudeData.pressure in kPa; the site uses hPa.
                let pressureHpa = data.pressure.doubleValue * 10
                guard pressureHpa.isFinite, (300...1100).contains(pressureHpa) else { return }
                self.lastError = nil
                self.readings.append(pressureHpa)
                if self.readings.count > 5 { self.readings.removeFirst() }
                self.sendPressure()
            }
        }

        func stopBarometer() {
            altimeter.stopRelativeAltitudeUpdates()
        }

        private func sendPressure() {
            guard let webView, !readings.isEmpty else { return }
            let mean = readings.reduce(0, +) / Double(readings.count)
            let spread = (readings.max() ?? mean) - (readings.min() ?? mean)
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let script = "window.BarrometrNativeReceivePressure?.(\(mean), \(timestamp), \(spread));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func sendError(_ message: String) {
            lastError = message
            guard let webView,
                  let encoded = try? JSONEncoder().encode(message),
                  let literal = String(data: encoded, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.BarrometrNativeSetError?.(\(literal));",
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            sendPressure()
            if let lastError { sendError(lastError) }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "barrometrStore",
                  let state = message.body as? String,
                  state.utf8.count < 1_000_000 else { return }
            UserDefaults.standard.set(state, forKey: "barrometr-site-state")
        }
    }
}
