import Foundation

final class Telemetry: @unchecked Sendable {
    struct Config: Sendable {
        var key: String?
        var host = URL(string: "https://us.i.posthog.com")!
        var allowed = true
        var batchSize = 20
        var capacity = 200
        var flushEvery: Duration = .seconds(60)
    }

    struct Pending: Sendable, Equatable {
        let uuid: String
        let name: String
        let properties: [String: TelemetryValue]
        let at: Date
    }

    static let shared = Telemetry(config: .fromEnvironment())

    private let config: Config
    private let transport: any Transport
    private let metrics: Metrics
    private let lock = NSLock()

    private var queue: [Pending] = []
    private var consent = true
    private var installId = ""
    private var common: [String: TelemetryValue] = [:]
    private var flushing = false
    private var timer: Task<Void, Never>?

    init(config: Config, transport: any Transport = URLSessionTransport(), metrics: Metrics = Metrics()) {
        self.config = config
        self.transport = transport
        self.metrics = metrics
    }

    var isActive: Bool {
        lock.withLock { canSend }
    }

    private var canSend: Bool {
        config.allowed && consent && !installId.isEmpty && !(config.key ?? "").isEmpty
    }

    var pendingCount: Int { lock.withLock { queue.count } }

    func configure(installId: String, consent: Bool, common: [String: TelemetryValue]) {
        lock.withLock {
            self.installId = installId
            self.consent = consent
            self.common = common
            if !canSend { queue.removeAll() }
        }
    }

    func setConsent(_ on: Bool) {
        lock.withLock {
            consent = on
            if !on { queue.removeAll() }
        }
    }

    func setInstallId(_ id: String) {
        lock.withLock {
            installId = id
            queue.removeAll()
        }
    }

    func capture(_ event: TelemetryEvent, at date: Date = Date()) {
        let full: Bool = lock.withLock {
            guard canSend else { return false }
            queue.append(Pending(uuid: UUID().uuidString, name: event.name, properties: event.properties, at: date))
            if queue.count > config.capacity { queue.removeFirst(queue.count - config.capacity) }
            return queue.count >= config.batchSize
        }
        if full {
            Task.detached(priority: .utility) { [self] in await flush() }
        }
        startTimerIfNeeded()
    }

    func flush() async {
        let batch: [Pending]? = lock.withLock {
            guard canSend, !flushing, !queue.isEmpty else { return nil }
            flushing = true
            let taken = Array(queue.prefix(100))
            queue.removeFirst(taken.count)
            return taken
        }
        guard let batch else { return }
        let sent = await send(batch)
        lock.withLock {
            flushing = false
            guard !sent, canSend else { return }
            queue.insert(contentsOf: batch, at: 0)
            if queue.count > config.capacity { queue.removeLast(queue.count - config.capacity) }
        }
    }

    private func startTimerIfNeeded() {
        let start: Bool = lock.withLock {
            guard timer == nil, canSend else { return false }
            return true
        }
        guard start else { return }
        let every = config.flushEvery
        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every, tolerance: .seconds(5))
                guard let self else { return }
                await self.flush()
            }
        }
        let kept: Bool = lock.withLock {
            guard timer == nil else { return false }
            timer = task
            return true
        }
        if !kept { task.cancel() }
    }

    func body(for batch: [Pending]) -> Data? {
        let (id, shared, key) = lock.withLock { (installId, common, config.key ?? "") }
        let iso = ISO8601DateFormatter()
        let events = batch.map { p in
            OutgoingEvent(
                event: p.name,
                distinct_id: id,
                uuid: p.uuid,
                timestamp: iso.string(from: p.at),
                properties: shared.merging(p.properties) { _, own in own }
                    .merging(["$lib": .text("diple"), "$process_person_profile": .bool(false)]) { own, _ in own }
            )
        }
        return try? JSONEncoder().encode(OutgoingBatch(api_key: key, batch: events))
    }

    private func send(_ batch: [Pending]) async -> Bool {
        guard let payload = body(for: batch) else { return true }
        var req = URLRequest(url: config.host.appendingPathComponent("batch/"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload
        req.timeoutInterval = 15
        do {
            let (_, response) = try await transport.send(req)
            metrics.count(.requests)
            metrics.count(.bytesOut, by: payload.count)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status) || (400..<500).contains(status)
        } catch {
            return false
        }
    }

    private struct OutgoingBatch: Encodable {
        let api_key: String
        let batch: [OutgoingEvent]
    }

    private struct OutgoingEvent: Encodable {
        let event: String
        let distinct_id: String
        let uuid: String
        let timestamp: String
        let properties: [String: TelemetryValue]
    }
}

extension Telemetry.Config {
    static func fromEnvironment() -> Telemetry.Config {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        return make(info: info, env: ProcessInfo.processInfo.environment, arguments: CommandLine.arguments)
    }

    static func make(info: [String: Any], env: [String: String], arguments: [String]) -> Telemetry.Config {
        var c = Telemetry.Config()
        c.key = (info["DiplePostHogKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        #if DEBUG
        if let override = env["DIPLE_POSTHOG_KEY"], !override.isEmpty { c.key = override }
        #endif
        if let host = (info["DiplePostHogHost"] as? String).flatMap(URL.init(string:)) { c.host = host }
        let doNotTrack = ["1", "true", "yes"].contains((env["DO_NOT_TRACK"] ?? "").lowercased())
        let underTest = env["XCTestConfigurationFilePath"] != nil || arguments.contains { $0.contains("xctest") }
        let special = arguments.contains("--demo") || arguments.contains("--bench") || arguments.contains("--film")
        c.allowed = !doNotTrack && !underTest && !special
        return c
    }
}
