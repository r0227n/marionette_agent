import Darwin
import Foundation
import XCTest

/// A serial, loopback-only runner. XCTest owns every accessibility/input call.
final class NativeRunner: XCTestCase {
    @MainActor
    func testServe() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let token = env["MRA_NATIVE_TOKEN"], token.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil,
              let portText = env["MRA_NATIVE_PORT"], let port = UInt16(portText), port > 0,
              let device = env["SIMULATOR_UDID"],
              let bundle = env["MRA_APP_BUNDLE_ID"], !bundle.isEmpty else {
            throw RunnerError.invalidConfiguration
        }
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw RunnerError.transport }
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listener, 4) == 0 else { throw RunnerError.transport }
        let app = XCUIApplication(bundleIdentifier: bundle)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Never launch/activate the target or auto-dismiss system dialogs.
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { throw RunnerError.transport }
            defer { close(client) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var reply: [String: Any] = ["version": 1, "platform": "ios", "device": device, "ok": false]
            do {
                let request = try readRequest(client)
                guard request["token"] as? String == token,
                      request["device"] as? String == device,
                      request["platform"] as? String == "ios",
                      request["version"] as? Int == 1 else { throw RunnerError.invalidRequest }
                try checkDeadline(request)
                switch request["action"] as? String {
                case "snapshot":
                    let system = springboard.alerts.firstMatch.exists || app.state != .runningForeground
                    let target = system ? springboard : app
                    var rows: [[String: Any]] = []
                    try flatten(target.snapshot(), package: system ? "com.apple.springboard" : bundle, into: &rows)
                    try checkDeadline(request)
                    reply["elements"] = rows
                case "tap", "swipe":
                    // SpringBoard coordinates use the full display's point space.
                    let origin = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                    if request["action"] as? String == "tap" {
                        let point = try coordinates(request, "x", "y")
                        try checkDeadline(request)
                        origin.withOffset(point).tap()
                    } else {
                        let start = try coordinates(request, "startX", "startY")
                        let end = try coordinates(request, "endX", "endY")
                        guard start != end else { throw RunnerError.invalidRequest }
                        try checkDeadline(request)
                        origin.withOffset(start).press(forDuration: 0, thenDragTo: origin.withOffset(end), withVelocity: .default, thenHoldForDuration: 0)
                    }
                default: throw RunnerError.invalidRequest
                }
                reply["ok"] = true
            } catch RunnerError.expired {
                reply["code"] = "TIMEOUT"
            } catch RunnerError.invalidRequest {
                reply["code"] = "INVALID_ARGUMENT"
            } catch {
                reply["code"] = "BACKEND_ERROR"
            }
            // No exception descriptions or input/UI strings in diagnostics.
            if var data = try? JSONSerialization.data(withJSONObject: reply), data.count <= 8 * 1024 * 1024 {
                data.append(10)
                data.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let count = send(client, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                        if count <= 0 { break }
                        offset += count
                    }
                }
            }
        }
    }

    private func readRequest(_ client: Int32) throws -> [String: Any] {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < 16384 {
            guard recv(client, &byte, 1, 0) == 1 else { throw RunnerError.transport }
            if byte == 10 {
                guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RunnerError.invalidRequest }
                return request
            }
            data.append(byte)
        }
        throw RunnerError.invalidRequest
    }

    private func checkDeadline(_ request: [String: Any]) throws {
        guard let deadline = request["deadline"] as? Double, deadline.isFinite else { throw RunnerError.invalidRequest }
        guard Date().timeIntervalSince1970 * 1000 < deadline else { throw RunnerError.expired }
    }

    private func coordinates(_ request: [String: Any], _ xKey: String, _ yKey: String) throws -> CGVector {
        guard let x = request[xKey] as? Double, let y = request[yKey] as? Double,
              x.isFinite, y.isFinite, x >= 0, y >= 0, x <= 10_000_000, y <= 10_000_000 else { throw RunnerError.invalidRequest }
        return CGVector(dx: x, dy: y)
    }

    @MainActor
    private func flatten(_ node: XCUIElementSnapshot, package: String, into rows: inout [[String: Any]]) throws {
        guard rows.count < 10000 else { throw RunnerError.tooLarge }
        let frame = node.frame
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else { throw RunnerError.invalidRequest }
        let type: String
        switch node.elementType {
        case .application: type = "Application"
        case .button: type = "Button"
        case .alert: type = "Alert"
        case .staticText: type = "StaticText"
        case .image: type = "Image"
        case .scrollView: type = "ScrollView"
        case .cell: type = "Cell"
        case .textField: type = "TextField"
        default: type = "XCUIElementType(\(node.elementType.rawValue))"
        }
        rows.append([
            "type": type, "text": node.label, "identifier": node.identifier,
            "value": (node.value as? String) ?? "", "package": package,
            "enabled": node.isEnabled,
            "bounds": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height],
        ])
        for child in node.children { try flatten(child, package: package, into: &rows) }
    }
}

private enum RunnerError: Error {
    case invalidConfiguration, invalidRequest, transport, expired, tooLarge
}
