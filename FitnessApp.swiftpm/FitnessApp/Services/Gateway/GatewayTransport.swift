import Foundation

/// Shared HTTP machinery for every gateway call: bearer injection, one
/// refresh-and-retry on 401, error-envelope decoding, and a proper SSE
/// parser for streaming chat.
enum GatewayTransport {

    // MARK: - One-shot JSON POST

    /// POST a JSON body to an authenticated gateway path (e.g. "v1/chat",
    /// "v1/feedback"). On a 401 the access token is refreshed once and the
    /// request retried once. Non-2xx throws a decoded `GatewayError`.
    static func postJSON(path: String,
                         body: [String: Any],
                         timeout: TimeInterval = 30) async throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: body)
        return try await send(path: path, payload: payload, timeout: timeout, allowAuthRetry: true)
    }

    private static func send(path: String,
                             payload: Data,
                             timeout: TimeInterval,
                             allowAuthRetry: Bool) async throws -> Data {
        let request = try await makeRequest(path: path, payload: payload, timeout: timeout)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GatewayError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.http(0, "No HTTP response from gateway.")
        }
        if http.statusCode == 401, allowAuthRetry {
            // Access token dead → refresh once, retry once.
            _ = try await GatewayAuth.shared.refresh()
            return try await send(path: path, payload: payload, timeout: timeout, allowAuthRetry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayError(status: http.statusCode, data: data)
        }
        return data
    }

    // MARK: - Streaming chat (SSE)

    /// POST /v1/chat with `"stream": true` in the body and parse the
    /// `text/event-stream` response. Yields one `Data` element per SSE event
    /// — each event's payload is a single Vertex-shaped JSON chunk, exactly
    /// what the old streamGenerateContent emitted per object.
    ///
    /// Auth (including the 401-refresh-retry) happens BEFORE the stream is
    /// handed back, so a thrown error here means the stream never started.
    static func streamChat(body: [String: Any],
                           idleTimeout: TimeInterval = 60) async throws -> AsyncThrowingStream<Data, Error> {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let bytes = try await openStream(payload: payload, timeout: idleTimeout, allowAuthRetry: true)

        return AsyncThrowingStream<Data, Error> { continuation in
            let reader = Task {
                // SSE framing: events are separated by blank lines; payload
                // lines start with "data:"; lines starting with ":" are
                // comments (keep-alives). Lines are split manually on LF
                // (stripping a trailing CR, so CRLF framing is tolerated) —
                // `AsyncLineSequence` can't be used here because it swallows
                // empty lines, which are the event boundaries.
                var eventData: [String] = []

                func flushEvent() {
                    guard !eventData.isEmpty else { return }
                    let joined = eventData.joined(separator: "\n")
                    eventData = []
                    // Tolerate a terminal sentinel if the server ever sends one.
                    guard joined != "[DONE]", !joined.isEmpty else { return }
                    continuation.yield(Data(joined.utf8))
                }

                func consumeLine(_ raw: [UInt8]) {
                    var lineBytes = raw
                    if lineBytes.last == 0x0D { lineBytes.removeLast() }   // CRLF
                    let line = String(decoding: lineBytes, as: UTF8.self)
                    if line.isEmpty {                       // event boundary
                        flushEvent()
                    } else if line.hasPrefix(":") {         // comment / keep-alive
                        return
                    } else if line.hasPrefix("data:") {
                        var value = String(line.dropFirst(5))
                        if value.hasPrefix(" ") { value.removeFirst() }
                        eventData.append(value)
                    }
                    // Other SSE fields (event:, id:, retry:) are ignored.
                }

                do {
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == 0x0A {                   // LF
                            if Task.isCancelled { break }
                            consumeLine(lineBuffer)
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty { consumeLine(lineBuffer) }
                    flushEvent()                                // final unterminated event
                    continuation.finish()
                } catch {
                    flushEvent()
                    continuation.finish(throwing: GatewayError.network(underlying: error))
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    /// Open the streaming connection and validate the response status.
    /// On 401: refresh once, reopen once. On other non-2xx: drain the error
    /// body (it's a small JSON envelope, not a stream) and throw.
    private static func openStream(payload: Data,
                                   timeout: TimeInterval,
                                   allowAuthRetry: Bool) async throws -> URLSession.AsyncBytes {
        let request = try await makeRequest(path: "v1/chat", payload: payload, timeout: timeout)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw GatewayError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.http(0, "No HTTP response from gateway.")
        }
        if http.statusCode == 401, allowAuthRetry {
            _ = try await GatewayAuth.shared.refresh()
            return try await openStream(payload: payload, timeout: timeout, allowAuthRetry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            do {
                for try await byte in bytes {
                    body.append(byte)
                    if body.count > 64 * 1024 { break }   // error envelopes are tiny
                }
            } catch {}
            throw GatewayError(status: http.statusCode, data: body)
        }
        return bytes
    }

    // MARK: - Request assembly

    /// Build an authenticated POST request. Throws `.notConfigured` when no
    /// base URL is set and `.notSignedIn` / `.unauthorized` from the auth layer.
    private static func makeRequest(path: String,
                                    payload: Data,
                                    timeout: TimeInterval) async throws -> URLRequest {
        guard let url = GatewayConfig.url(for: path) else {
            throw GatewayError.notConfigured
        }
        let token = try await GatewayAuth.shared.validAccessToken()
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        return request
    }
}
