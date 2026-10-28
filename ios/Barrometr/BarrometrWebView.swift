import CoreMotion
import CoreLocation
import SwiftUI
import WebKit

struct BarrometrWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "barrometrStore")
        contentController.add(context.coordinator, name: "barrometrPose")

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
        coordinator.stopPose()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "barrometrStore")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "barrometrPose")
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, CLLocationManagerDelegate {
        weak var webView: WKWebView?
        private let altimeter = CMAltimeter()
        private let locationManager = CLLocationManager()
        private var readings: [Double] = []
        private var lastError: String?
        private var latestLocation: CLLocation?
        private var latestHeading: CLHeading?
        private var wantsLocation = false
        private var wantsHeading = false

        func startPose(heading: Bool = false) {
            wantsLocation = true
            if heading { wantsHeading = true }
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if wantsLocation { locationManager.startUpdatingLocation() }
                if wantsHeading && CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            default:
                sendPoseError("Доступ к геопозиции отключён в настройках iPhone.")
            }
        }

        func stopPose() {
            wantsLocation = false
            wantsHeading = false
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if wantsLocation { manager.startUpdatingLocation() }
                if wantsHeading && CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            case .denied, .restricted:
                sendPoseError("Разрешите доступ к геопозиции в настройках iPhone.")
            default: break
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let value = locations.last, value.horizontalAccuracy >= 0 else { return }
            latestLocation = value
            sendPose()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
            latestHeading = heading
            sendPose()
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            sendPoseError("Не удалось получить геопозицию: \(error.localizedDescription)")
        }

        private func sendPose() {
            guard let webView, let value = latestLocation else { return }
            let compass = latestHeading.flatMap { $0.trueHeading >= 0 ? $0.trueHeading : nil }
            let headingValue = compass.map { String($0) } ?? "null"
            let headingAccuracy = latestHeading.flatMap { $0.headingAccuracy >= 0 ? $0.headingAccuracy : nil }
            let accuracyValue = headingAccuracy.map { String($0) } ?? "null"
            let timestamp = Int(value.timestamp.timeIntervalSince1970 * 1000)
            let script = "window.BarrometrNativeReceivePose?.(\(value.coordinate.latitude), \(value.coordinate.longitude), \(value.horizontalAccuracy), \(headingValue), \(accuracyValue), \(timestamp));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func sendPoseError(_ message: String) {
            guard let webView,
                  let encoded = try? JSONEncoder().encode(message),
                  let literal = String(data: encoded, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.BarrometrNativePoseError?.(\(literal));", completionHandler: nil)
        }

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
                // Apple передаёт CMAltitudeData.pressure в кПа, а сайт использует гПа.
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
            sendPose()
            if let lastError { sendError(lastError) }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "barrometrPose", let command = message.body as? String {
                if command == "start" { startPose() }
                if command == "heading" { startPose(heading: true) }
                if command == "stop" { stopPose() }
                return
            }
            guard message.name == "barrometrStore",
                  let state = message.body as? String,
                  state.utf8.count < 1_000_000 else { return }
            UserDefaults.standard.set(state, forKey: "barrometr-site-state")
        }
    }
}
