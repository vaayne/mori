import Foundation

/// Agent state is deliberately smaller than the macOS model: these are the only
/// values emitted by Mori's tmux hooks. Everything else is rendered as unknown
/// rather than being guessed from terminal output.
enum MoriAgentState: String, CaseIterable, Equatable, Sendable {
    case unknown
    case working
    case waiting
    case done

    var priority: Int {
        switch self {
        case .waiting: 3
        case .working: 2
        case .done: 1
        case .unknown: 0
        }
    }
}

struct AgentMetadata: Equatable, Sendable {
    let state: MoriAgentState
    let name: String?

    static let unknown = Self(state: .unknown, name: nil)
}

/// One safe, host-wide agent record. The fixed tmux query is the sole source;
/// this never becomes a general remote-navigation command surface.
struct AgentAttentionTarget: Identifiable, Equatable, Sendable {
    let sessionName: String
    let windowID: UInt64
    let windowTitle: String
    let paneID: UInt64
    let metadata: AgentMetadata

    var id: UInt64 { paneID }
}

struct AgentAttentionSummary: Equatable, Sendable {
    let waiting: Int
    let working: Int
    let done: Int

    var total: Int { waiting + working + done }
}

/// App-local projection of the facade's fixed query result. It intentionally
/// carries no tmux-controller detail across the terminal boundary.
struct AgentMetadataQueryResult: Sendable {
    let succeeded: Bool
    let body: String
}

/// Parses the one bounded, fixed-format tmux response. Every field is untrusted
/// remote text. A malformed or duplicate source record invalidates the whole
/// response; MoriRemote shadow sessions are discarded before pane de-duplication.
struct AgentMetadataResponseParser: Sendable {
    static let maximumResponseBytes = 65_536
    static let maximumRecords = 512
    static let maximumSessionNameLength = 128
    static let maximumWindowTitleLength = 256
    static let maximumNameLength = 64

    func parse(_ body: String) -> [AgentAttentionTarget] {
        guard body.utf8.count <= Self.maximumResponseBytes else { return [] }
        let records = body.split(separator: "\n", omittingEmptySubsequences: true)
        // Never prefix-truncate: an injected valid row can otherwise be hidden
        // after the cap, and a duplicate must invalidate the whole response.
        guard records.count <= Self.maximumRecords else { return [] }
        var result: [AgentAttentionTarget] = []
        var seenPaneIDs = Set<UInt64>()
        for line in records {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 6,
                  let sessionName = normalizeText(fields[0], maximumLength: Self.maximumSessionNameLength),
                  let windowID = parseWindowID(fields[1]),
                  let windowTitle = normalizeText(fields[2], maximumLength: Self.maximumWindowTitleLength),
                  let paneID = parsePaneID(fields[3])
            else { return [] }
            guard !isMoriRemoteShadow(sessionName) else { continue }
            guard seenPaneIDs.insert(paneID).inserted else { return [] }
            result.append(.init(
                sessionName: sessionName,
                windowID: windowID,
                windowTitle: windowTitle,
                paneID: paneID,
                metadata: .init(state: normalizeState(fields[4]), name: normalizeName(fields[5]))
            ))
        }
        return result
    }

    private func parsePaneID(_ field: Substring) -> UInt64? {
        guard field.first == "%", field.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return UInt64(field.dropFirst())
    }

    private func parseWindowID(_ field: Substring) -> UInt64? {
        guard field.first == "@", field.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return UInt64(field.dropFirst())
    }

    private func normalizeState(_ field: Substring) -> MoriAgentState {
        MoriAgentState(rawValue: String(field)) ?? .unknown
    }

    private func normalizeName(_ field: Substring) -> String? {
        normalizeText(field, maximumLength: Self.maximumNameLength)
    }

    private func normalizeText(_ field: Substring, maximumLength: Int) -> String? {
        let value = String(field)
        guard !value.isEmpty, value.count <= maximumLength,
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else { return nil }
        return value
    }

    private func isMoriRemoteShadow(_ sessionName: String) -> Bool {
        guard let marker = sessionName.range(of: "--mori-remote-", options: .backwards) else { return false }
        return UUID(uuidString: String(sessionName[marker.upperBound...])) != nil
    }
}

/// Projects response records only onto panes the active facade topology owns.
/// A successful response is authoritative, so missing or cleared options erase
/// old metadata; a failed response intentionally yields unknown instead.
struct AgentMetadataProjection: Sendable {
    static func retain(_ metadata: [UInt64: AgentMetadata], paneIDs: [UInt64]) -> [UInt64: AgentMetadata] {
        var projection: [UInt64: AgentMetadata] = [:]
        for paneID in paneIDs where projection[paneID] == nil {
            projection[paneID] = metadata[paneID] ?? .unknown
        }
        return projection
    }

    static func merge(_ records: [AgentAttentionTarget], paneIDs: [UInt64]) -> [UInt64: AgentMetadata] {
        // Corrupt/native snapshots must not crash the UI. First occurrence wins,
        // matching the topology order used everywhere else in the projection.
        let metadataByPaneID = Dictionary(uniqueKeysWithValues: records.map { ($0.paneID, $0.metadata) })
        return retain(metadataByPaneID, paneIDs: paneIDs)
    }
}

enum AgentAttentionProjection {
    static func ordered(_ records: [AgentAttentionTarget]) -> [AgentAttentionTarget] {
        records
            .filter { $0.metadata.state != .unknown }
            .sorted { lhs, rhs in
                if lhs.metadata.state.priority != rhs.metadata.state.priority {
                    return lhs.metadata.state.priority > rhs.metadata.state.priority
                }
                let sessionOrder = lhs.sessionName.localizedStandardCompare(rhs.sessionName)
                if sessionOrder != .orderedSame { return sessionOrder == .orderedAscending }
                if lhs.windowID != rhs.windowID { return lhs.windowID < rhs.windowID }
                return lhs.paneID < rhs.paneID
            }
    }

    static func summary(_ records: [AgentAttentionTarget]) -> AgentAttentionSummary {
        .init(
            waiting: records.count { $0.metadata.state == .waiting },
            working: records.count { $0.metadata.state == .working },
            done: records.count { $0.metadata.state == .done }
        )
    }
}

/// A visible runtime owns one projector. It has no tmux parser or transport:
/// the supplied query is the facade's fixed correlated metadata result.
/// Cancellation and the immutable instance ID reject late replies.
@MainActor
final class AgentMetadataProjector {
    static let refreshInterval: Duration = .seconds(5)

    private let instanceID: UUID
    private let query: @MainActor () async -> AgentMetadataQueryResult
    private let parser = AgentMetadataResponseParser()
    private var paneIDs: [UInt64] = []
    private var refreshTask: Task<Void, Never>?
    private var visible = false
    private var stopped = false
    private var queryInFlight = false
    /// Hiding has no native command cancellation primitive. This generation
    /// fence lets a newly-visible runtime issue a fresh query while dropping an
    /// old completion that arrives after presentation changed.
    private var queryGeneration: UInt64 = 0

    private(set) var metadata: [UInt64: AgentMetadata] = [:]
    private(set) var attention: [AgentAttentionTarget] = []
    private(set) var lastFailure: String?
    var onChange: (@MainActor () -> Void)?

    init(instanceID: UUID, query: @escaping @MainActor () async -> AgentMetadataQueryResult) {
        self.instanceID = instanceID
        self.query = query
    }

    func topologyDidChange(paneIDs: [UInt64]) {
        guard !stopped else { return }
        self.paneIDs = paneIDs
        metadata = AgentMetadataProjection.retain(metadata, paneIDs: paneIDs)
        onChange?()
        refreshImmediately()
    }

    func setVisible(_ visible: Bool) {
        guard !stopped, self.visible != visible else { return }
        self.visible = visible
        if visible {
            refreshImmediately()
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    guard !Task.isCancelled else { return }
                    self?.refreshImmediately()
                }
            }
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            queryGeneration &+= 1
            queryInFlight = false
            metadata = [:]
            attention = []
            onChange?()
        }
    }

    /// Foregrounding only refreshes already-visible metadata. It never creates a
    /// transport or invokes the reconnect policy.
    func foregrounded() { refreshImmediately() }

    func stop() {
        guard !stopped else { return }
        stopped = true
        queryGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        queryInFlight = false
        metadata = [:]
        attention = []
    }

    private func refreshImmediately() {
        guard visible, !stopped, !paneIDs.isEmpty, !queryInFlight else { return }
        queryInFlight = true
        let responseInstanceID = instanceID
        let responseGeneration = queryGeneration
        Task { [weak self] in
            guard let self else { return }
            let result = await self.query()
            self.receive(result, from: responseInstanceID, generation: responseGeneration)
        }
    }

    private func receive(_ result: AgentMetadataQueryResult, from responseInstanceID: UUID, generation: UInt64) {
        guard !stopped, responseInstanceID == instanceID, generation == queryGeneration, visible else { return }
        queryInFlight = false
        if result.succeeded {
            lastFailure = nil
            let records = parser.parse(result.body)
            metadata = AgentMetadataProjection.merge(records, paneIDs: paneIDs)
            attention = AgentAttentionProjection.ordered(records)
        } else {
            lastFailure = result.body
            metadata = AgentMetadataProjection.merge([], paneIDs: paneIDs)
            attention = []
        }
        onChange?()
    }
}
