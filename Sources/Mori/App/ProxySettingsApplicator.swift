import Foundation
import MoriTmux
import MoriUI

/// Persists proxy settings in UserDefaults and applies them as tmux global
/// environment variables so all Mori-managed sessions inherit the proxy.
enum ProxySettingsApplicator {

    private static let keyPrefix = "MoriProxy_"

    // MARK: - Persistence

    static func load() -> ProxySettingsModel {
        let ud = UserDefaults.standard
        return ProxySettingsModel(
            httpProxy: ud.string(forKey: keyPrefix + "http_proxy") ?? "",
            httpsProxy: ud.string(forKey: keyPrefix + "https_proxy") ?? "",
            allProxy: ud.string(forKey: keyPrefix + "all_proxy") ?? "",
            noProxy: ud.string(forKey: keyPrefix + "no_proxy") ?? ""
        )
    }

    static func save(_ model: ProxySettingsModel) {
        let ud = UserDefaults.standard
        ud.set(model.httpProxy, forKey: keyPrefix + "http_proxy")
        ud.set(model.httpsProxy, forKey: keyPrefix + "https_proxy")
        ud.set(model.allProxy, forKey: keyPrefix + "all_proxy")
        ud.set(model.noProxy, forKey: keyPrefix + "no_proxy")
    }

    // MARK: - Apply to tmux

    static func apply(_ model: ProxySettingsModel, tmuxBackend: TmuxBackend) async {
        for (envName, value) in model.allEntries {
            guard !Task.isCancelled else { return }
            do {
                if value.isEmpty {
                    try await tmuxBackend.unsetEnvironment(name: envName)
                } else {
                    try await tmuxBackend.setEnvironment(name: envName, value: value)
                }
            } catch {
                print("[ProxySettingsApplicator] Failed to set \(envName): \(error)")
            }
        }
    }
}
