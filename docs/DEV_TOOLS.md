# Local development tools

Ponytail **5.3.3** installed and enabled on 2026-11-09 from the author's [official repository](https://github.com/DietrichGebert/ponytail), using `codex plugin marketplace add DietrichGebert/ponytail` and `codex plugin add ponytail@ponytail`. Its supported default is explicitly `full`; other config was preserved. Six bundled skills are installed. It is a development instruction plugin, not an app dependency or a way to increase account limits.

Installed path: `C:/Users/Aryan/.codex/plugins/cache/ponytail/ponytail/5.3.3`. The installed lifecycle manifest contains SessionStart, SubagentStart and UserPromptSubmit hooks. Installation/enabling does not establish hook trust; review them through Codex `/hooks` before trusting, and reload/restart into a new session to pick up the plugin. The current chat can follow the skill instructions directly, but that is not proof automatic hooks ran. No hook-trust records were edited or bypassed.

The plugin has no guaranteed token-savings percentage for Linqo. Prefer necessary changes, existing libraries and bounded verification, while preserving security, data-loss protection, accessibility and requested scope. The Claude-only usage band is not claimed to work in Codex. Project milestone backups contain this setup record, not the external global plugin installation.

## Iris setup cancelled — 2026-11-09

The owner requested Iris, then explicitly cancelled when Windows build tools were required. Its source includes Windows paths, but published binaries target macOS/Linux. Chrome is already installed; Rust/C++ tools were absent. Microsoft Build Tools setup returned 1602 (cancelled) and no Build Tools/Visual Studio Installer registration was found afterward. The verified Rust installer was downloaded but never executed. Removed only this attempt's `.tools/iris` checkout, `rustup-init.exe` and its checksum file; the empty installers directory was removed. No Iris MCP server was registered, and no Iris/Rust process or toolchain remains. Existing developer tools and unrelated Windows services were not removed.

The other linked projects were assessed, not installed: ECC overlaps existing coding skills; Jev MCP and Jev core add another web-agent stack/provider configuration; Fortress adds a separate Chromium engine; Artemis is the most directly relevant candidate for future Android workflow testing. No claimed benchmark savings are established on Linqo.

## Dodo Payments agent — 2026-11-10

Installed and verified `dodopayments@dodopayments` version **0.8.0** from the official `dodopayments/dodo-agent-plugin` marketplace. Its integration skill and remote OAuth MCP endpoint (`https://mcp.dodopayments.com/mcp`) are enabled. The CLI confirmed successful OAuth login on 2026-11-10; selected business/mode and merchant verification status still require confirmation. The current chat has not loaded Dodo tools yet. No API key was added to Linqo and no Flutter dependency, payment provider, live checkout or product limit was changed. The agent installation and OAuth credentials are outside the project and are not included in project archives.

Dodo publishes support for Indian INR cards/UPI and international sales, but Linqo merchant approval, payout eligibility and actual checkout coverage remain unverified. Keep Cashfree intact until those gates pass. Begin account access in test mode; donations remain separate through Buy Me a Coffee.
