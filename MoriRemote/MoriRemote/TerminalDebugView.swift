#if DEBUG
import MoriTerminal
import SwiftUI

/// Debug screen that exercises SwiftTermRenderer without SSH.
/// Shows the terminal, feeds mock data, and verifies rendering works.
struct TerminalDebugView: View {
    @State private var log: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            TerminalView(
                onRendererReady: { renderer in
                    log.append("renderer ready")

                    let size = renderer.gridSize()
                    log.append("grid: \(size.cols)x\(size.rows)")

                    renderer.inputHandler = { data in
                        let text = String(data: data, encoding: .utf8) ?? data.description
                        log.append("input: \(text.debugDescription)")
                    }

                    renderer.sizeChangeHandler = { cols, rows in
                        log.append("resize: \(cols)x\(rows)")
                    }

                    // Feed mock terminal output — ANSI colored text + prompt
                    let mockOutput = [
                        "\u{1b}[1;32m$ \u{1b}[0mecho 'Hello from SwiftTerm!'\r\n",
                        "Hello from SwiftTerm!\r\n",
                        "\u{1b}[1;34m$ \u{1b}[0mls -la\r\n",
                        "total 42\r\n",
                        "drwxr-xr-x  10 user  staff   320 Mar 29 12:00 \u{1b}[1;36m.\u{1b}[0m\r\n",
                        "drwxr-xr-x   5 user  staff   160 Mar 29 11:00 \u{1b}[1;36m..\u{1b}[0m\r\n",
                        "-rw-r--r--   1 user  staff  1234 Mar 29 12:00 README.md\r\n",
                        "-rwxr-xr-x   1 user  staff  5678 Mar 29 12:00 \u{1b}[1;32mapp\u{1b}[0m\r\n",
                        "\u{1b}[1;32m$ \u{1b}[0m\u{1b}[5m▊\u{1b}[0m",
                    ].joined()

                    if let data = mockOutput.data(using: .utf8) {
                        renderer.feedBytes(data)
                        log.append("fed \(data.count) bytes")
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Debug log at bottom
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 120)
            .background(.ultraThinMaterial)
        }
    }
}
#endif
