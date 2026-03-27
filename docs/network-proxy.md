# Network Proxy Settings

Mori can configure proxy environment variables for all terminal sessions it manages. Proxy settings are applied via `tmux set-environment -g`, which sets global environment variables on the tmux server.

## Proxy Modes

Open **Settings > Network** to configure proxy mode:

| Mode | Description |
|------|-------------|
| **System proxy** | Reads proxy settings from macOS system configuration (`scutil --proxy`). Fields are read-only. |
| **Manual configuration** | Specify HTTP, HTTPS, SOCKS proxy URLs and bypass list manually. |
| **No proxy** | Clears all proxy environment variables from the tmux server. |

## Environment Variables

Mori sets both lowercase and uppercase variants for maximum compatibility:

- `http_proxy` / `HTTP_PROXY`
- `https_proxy` / `HTTPS_PROXY`
- `all_proxy` / `ALL_PROXY` (SOCKS proxy)
- `no_proxy` / `NO_PROXY` (bypass list)

## Important: New Tabs/Panes Only

Proxy changes **only affect new terminal tabs and panes**. Existing shells keep their current environment because tmux's `set-environment -g` sets the environment inherited by new windows — it cannot modify the environment of already-running processes.

If you need to update an existing shell after changing proxy settings, run the export commands manually:

```bash
# After changing proxy in Settings > Network, run in existing shells:
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
export no_proxy=localhost,127.0.0.1

# Or to clear proxy:
unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
```

Alternatively, open a new tab (⌘T) which will automatically inherit the updated proxy settings.

## System Proxy Detection

When using **System proxy** mode, Mori reads the macOS network proxy configuration via `scutil --proxy`. This includes:

- HTTP proxy (System Settings > Network > Proxies > Web Proxy)
- HTTPS proxy (System Settings > Network > Proxies > Secure Web Proxy)
- SOCKS proxy (System Settings > Network > Proxies > SOCKS Proxy)
- Bypass list (System Settings > Network > Proxies > Bypass proxy settings)

Note: System proxy values are read at the time you select "System proxy" mode or click Apply. If you change macOS proxy settings afterward, click Apply again to re-read them.
