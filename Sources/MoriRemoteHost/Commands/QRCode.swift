import ArgumentParser
import Foundation

/// Generate and display a QR code for pairing.
struct QRCode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "qrcode",
        abstract: .localized("Generate a QR code for iOS pairing.")
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Relay server base URL (e.g., https://relay.example.com)")))
    var relayURL: String

    @Option(name: .long, help: ArgumentHelp(.localized("Pre-generated token (skips /pair request if provided)")))
    var token: String?

    @Flag(name: .long, help: ArgumentHelp(.localized("Output QR code as PNG data to stdout instead of terminal ASCII")))
    var png: Bool = false

    func run() async throws {
        let pairingToken: String

        if let token {
            pairingToken = token
        } else {
            // Request a new pairing token from the relay
            pairingToken = try await requestPairingToken(relayURL: relayURL)
        }

        let pairingURL = "mori-relay://\(relayURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))/\(pairingToken)"

        if png {
            guard let pngData = QRCodeGenerator.generatePNG(from: pairingURL) else {
                print(String.localized("Failed to generate QR code PNG"))
                throw ExitCode.failure
            }
            FileHandle.standardOutput.write(pngData)
        } else {
            let ascii = QRCodeGenerator.generateASCII(from: pairingURL)
            if let ascii {
                print(String.localized("Scan this QR code with Mori Remote on your iOS device:"))
                print()
                print(ascii)
                print()
                print("Pairing URL: \(pairingURL)")
            } else {
                print(String.localized("Failed to generate QR code. Pairing URL: \(pairingURL)"))
            }
        }
    }

    private func requestPairingToken(relayURL: String) async throws -> String {
        let pairURL = relayURL.hasSuffix("/") ? "\(relayURL)pair" : "\(relayURL)/pair"
        guard let url = URL(string: pairURL) else {
            throw ValidationError("Invalid relay URL: \(relayURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ValidationError("Failed to request pairing token from relay")
        }

        struct PairResponse: Codable {
            let token: String
        }

        let pairResponse = try JSONDecoder().decode(PairResponse.self, from: data)
        return pairResponse.token
    }
}
