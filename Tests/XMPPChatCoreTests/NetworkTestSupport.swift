//
//  NetworkTestSupport.swift
//  XMPPChatCoreTests
//
//  Test-only HTTP stub for the push, refresh and XMPP-token calls. It
//  records each request (method, URL, Authorization, JSON body) and answers
//  from a queue, so tests can assert the wire shape and the retry order.
//

import XCTest
@testable import XMPPChatCore

final class StubURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: Data
        let headers: [String: String]

        static func json(_ status: Int, _ object: [String: Any]) -> Reply {
            Reply(status: status, body: try! JSONSerialization.data(withJSONObject: object), headers: [:])
        }

        static func empty(_ status: Int) -> Reply {
            Reply(status: status, body: Data("{}".utf8), headers: [:])
        }
    }

    struct Captured {
        let method: String
        let url: URL
        let authorization: String?
        let body: [String: Any]?
    }

    /// Answers for the next requests, in order. An empty queue answers 500.
    static var replies: [Reply] = []
    static var captured: [Captured] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.captured.append(Captured(
            method: request.httpMethod ?? "",
            url: url,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: Self.jsonBody(of: request)
        ))
        let reply = Self.replies.isEmpty ? Reply.empty(500) : Self.replies.removeFirst()
        let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func jsonBody(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            stream.close()
            data = collected
        }
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Base class: stubbed transport, a baseUrl/appId config, and a clean user store.
@MainActor
class NetworkTestCase: XCTestCase {
    static let baseURL = "https://api.test.example/v1"

    override func setUp() async throws {
        StubURLProtocol.replies = []
        StubURLProtocol.captured = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        RESTTransport.session = URLSession(configuration: configuration)

        ConfigStore.shared.reset()
        var config = ChatConfig()
        config.baseUrl = Self.baseURL
        config.appId = "app1"
        ConfigStore.shared.mergeConfig(config)

        UserStore.shared.clearUser()
        UserStore.shared.token = "user-token"
        UserStore.shared.refreshToken = "refresh-1"
        UserStore.shared.currentUser = User(id: "u1", token: "user-token", refreshToken: "refresh-1")
    }

    override func tearDown() async throws {
        RESTTransport.session = .shared
        ConfigStore.shared.reset()
        UserStore.shared.clearUser()
        StubURLProtocol.replies = []
        StubURLProtocol.captured = []
    }

    /// The only captured request, asserting there is exactly one.
    func onlyCall(file: StaticString = #filePath, line: UInt = #line) -> StubURLProtocol.Captured {
        XCTAssertEqual(StubURLProtocol.captured.count, 1, file: file, line: line)
        return StubURLProtocol.captured[0]
    }

    static func makeJWT(exp: TimeInterval) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: ["exp": exp, "sub": "u1"]))
        return "\(header).\(payload).signature"
    }
}
