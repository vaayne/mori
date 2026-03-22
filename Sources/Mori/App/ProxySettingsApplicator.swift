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
        var model = ProxySettingsModel(
            mode: ProxyMode(rawValue: ud.string(forKey: keyPrefix + "mode") ?? "") ?? .none,
            httpProxy: ud.string(forKey: keyPrefix + "http_proxy") ?? "",
            httpsProxy: ud.string(forKey: keyPrefix + "https_proxy") ?? "",
            sameForHTTPS: ud.object(forKey: keyPrefix + "same_for_https") as? Bool ?? true,
            socksProxy: ud.string(forKey: keyPrefix + "socks_proxy") ?? "",
            noProxy: ud.string(forKey: keyPrefix + "no_proxy") ?? ""
        )
        // Auto-populate from system proxy when in system mode
        if model.mode == .system {
            let system = readSystemProxy()
            model.httpProxy = system.httpProxy
            model.httpsProxy = system.httpsProxy
            model.socksProxy = system.socksProxy
            model.noProxy = system.noProxy
            model.sameForHTTPS = false
        }
        return model
    }

    static func save(_ model: ProxySettingsModel) {
        let ud = UserDefaults.standard
        ud.set(model.mode.rawValue, forKey: keyPrefix + "mode")
        ud.set(model.httpProxy, forKey: keyPrefix + "http_proxy")
        ud.set(model.httpsProxy, forKey: keyPrefix + "https_proxy")
        ud.set(model.sameForHTTPS, forKey: keyPrefix + "same_for_https")
        ud.set(model.socksProxy, forKey: keyPrefix + "socks_proxy")
        ud.set(model.noProxy, forKey: keyPrefix + "no_proxy")
    }

    // MARK: - System Proxy Detection

    /// Read proxy settings from macOS system configuration via `scutil --proxy`.
    static func readSystemProxy() -> ProxySettingsModel {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--proxy"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProxySettingsModel()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return ProxySettingsModel()
        }

        return parseScutilProxy(output)
    }

    /// Parse the dictionary output of `scutil --proxy`.
    private static func parseScutilProxy(_ output: String) -> ProxySettingsModel {
        // Helper to extract a value for a key like "  HTTPProxy : 127.0.0.1"
        func value(for key: String) -> String? {
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key) : ") {
                    return String(trimmed.dropFirst("\(key) : ".count))
                }
            }
            return nil
        }

        func intValue(for key: String) -> Int? {
            guard let s = value(for: key) else { return nil }
            return Int(s)
        }

        func isEnabled(_ key: String) -> Bool {
            intValue(for: key) == 1
        }

        var httpProxy = ""
        var httpsProxy = ""
        var socksProxy = ""

        if isEnabled("HTTPEnable"),
           let host = value(for: "HTTPProxy") {
            let port = intValue(for: "HTTPPort") ?? 80
            httpProxy = "http://\(host):\(port)"
        }

        if isEnabled("HTTPSEnable"),
           let host = value(for: "HTTPSProxy") {
            let port = intValue(for: "HTTPSPort") ?? 443
            httpsProxy = "http://\(host):\(port)"
        }

        if isEnabled("SOCKSEnable"),
           let host = value(for: "SOCKSProxy") {
            let port = intValue(for: "SOCKSPort") ?? 1080
            socksProxy = "socks5://\(host):\(port)"
        }

        // Parse ExceptionsList array
        var exceptions: [String] = []
        var inExceptions = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ExceptionsList") {
                inExceptions = true
                continue
            }
            if inExceptions {
                if trimmed == "}" {
                    inExceptions = false
                    continue
                }
                // Lines like "0 : *.local"
                if let colonIndex = trimmed.firstIndex(of: ":") {
                    let val = trimmed[trimmed.index(after: colonIndex)...]
                        .trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { exceptions.append(val) }
                }
            }
        }

        return ProxySettingsModel(
            mode: .system,
            httpProxy: httpProxy,
            httpsProxy: httpsProxy,
            sameForHTTPS: false,
            socksProxy: socksProxy,
            noProxy: exceptions.joined(separator: ",")
        )
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
