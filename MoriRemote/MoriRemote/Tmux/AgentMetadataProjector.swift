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

/// Parses the one bounded, fixed-format tmux response. Pane options are
/// untrusted remote text: state is exact-match only, and labels cannot smuggle
/// a row/delimiter into the navigation projection.
struct AgentMetadataResponseParser: Sendable {
    static let maximumResponseBytes = 65_536
    static let maximumRecords = 512
    static let maximumNameLength = 64

    func parse(_ body: String) -> [TmuxPaneID: AgentMetadata] {
        guard body.utf8.count <= Self.maximumResponseBytes else { return [:] }
        let records = body.split(separator: "\n", omittingEmptySubsequences: true)
        // Never prefix-truncate: an injected valid row can otherwise be hidden
        // after the cap, and a duplicate must invalidate the whole response.
        guard records.count <= Self.maximumRecords else { return [:] }
        var result: [TmuxPaneID: AgentMetadata] = [:]
        var seenPaneIDs = Set<TmuxPaneID>()
        for line in records {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let first = fields.first, let paneID = parsePaneID(first) else { continue }
            guard seenPaneIDs.insert(paneID).inserted else { return [:] }
            guard fields.count == 3 else { continue }
            result[paneID] = .init(state: normalizeState(fields[1]), name: normalizeName(fields[2]))
        }
        return result
    }

    private func parsePaneID(_ field: Substring) -> TmuxPaneID? {
        guard field.first == "%", field.dropFirst().allSatisfy(\.isNumber),
              let rawValue = UInt64(field.dropFirst())
        else { return nil }
        return .init(rawValue)
    }

    private func normalizeState(_ field: Substring) -> MoriAgentState {
        MoriAgentState(rawValue: String(field)) ?? .unknown
    }

    private func normalizeName(_ field: Substring) -> String? {
        let value = String(field)
        guard !value.isEmpty, value.count <= Self.maximumNameLength,
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else { return nil }
        return value
    }
}

/// Projects response records only onto panes the active Ghostty topology owns.
/// A successful response is authoritative, so missing or cleared options erase
/// old metadata; a failed response intentionally yields unknown instead.
struct AgentMetadataProjection: Sendable {
    static func merge(_ records: [TmuxPaneID: AgentMetadata], into topology: TmuxSessionController.Topology?) -> [TmuxPaneID: AgentMetadata] {
        guard let topology else { return [:] }
        // Corrupt/native snapshots must not crash the UI. First occurrence wins,
        // matching the topology order used everywhere else in the projection.
        var projection: [TmuxPaneID: AgentMetadata] = [:]
        for pane in topology.panes where projection[pane.id] == nil {
            projection[pane.id] = records[pane.id] ?? .unknown
        }
        return projection
    }
}

/// The size class selects surrounding chrome, never a terminal identity. Keeping
/// this policy explicit makes rotation/split-view regressions deterministic.
enum RemoteTerminalPresentation: Sendable {
    enum Mode: Sendable { case compact, regular }
    static func identity(for runtimeInstanceID: UUID, mode: Mode) -> UUID {
        _ = mode
        return runtimeInstanceID
    }
}

/// A visible runtime owns one projector. It has no tmux parser or transport:
/// the supplied query closure is the existing Ghostty-correlated controller
/// boundary. Cancellation and the immutable instance ID reject late replies.
@MainActor
final class AgentMetadataProjector {
    static let refreshInterval: Duration = .seconds(5)

    private let instanceID: UUID
    private let query: (@escaping @Sendable (TmuxSessionController.CommandResult) -> Void) -> Void
    private let parser = AgentMetadataResponseParser()
    private var topology: TmuxSessionController.Topology?
    private var refreshTask: Task<Void, Never>?
    private var visible = false
    private var stopped = false
    private var queryInFlight = false
    /// Hiding has no native command cancellation primitive. This generation
    /// fence lets a newly-visible runtime issue a fresh query while dropping an
    /// old completion that arrives after presentation changed.
    private var queryGeneration: UInt64 = 0

    private(set) var metadata: [TmuxPaneID: AgentMetadata] = [:]
    private(set) var lastFailure: String?
    var onChange: (@MainActor () -> Void)?

    init(instanceID: UUID, query: @escaping (@escaping @Sendable (TmuxSessionController.CommandResult) -> Void) -> Void) {
        self.instanceID = instanceID
        self.query = query
    }

    func topologyDidChange(_ topology: TmuxSessionController.Topology) {
        guard !stopped else { return }
        self.topology = topology
        metadata = AgentMetadataProjection.merge(metadata, into: topology)
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
    }

    private func refreshImmediately() {
        guard visible, !stopped, topology != nil, !queryInFlight else { return }
        queryInFlight = true
        let responseInstanceID = instanceID
        let responseGeneration = queryGeneration
        query { [weak self] result in
            Task { @MainActor in self?.receive(result, from: responseInstanceID, generation: responseGeneration) }
        }
    }

    private func receive(_ result: TmuxSessionController.CommandResult, from responseInstanceID: UUID, generation: UInt64) {
        guard !stopped, responseInstanceID == instanceID, generation == queryGeneration, visible else { return }
        queryInFlight = false
        switch result.status {
        case .success:
            lastFailure = nil
            metadata = AgentMetadataProjection.merge(parser.parse(result.body), into: topology)
        case .skipped, .error:
            lastFailure = result.body
            metadata = AgentMetadataProjection.merge([:], into: topology)
        }
        onChange?()
    }
}
