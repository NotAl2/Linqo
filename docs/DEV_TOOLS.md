# Local development tools

Ponytail **5.3.3** installed and enabled on 2026-11-09 from the author's [official repository](https://github.com/DietrichGebert/ponytail), using `codex plugin marketplace add DietrichGebert/ponytail` and `codex plugin add ponytail@ponytail`. Its supported default is explicitly `full`; other config was preserved. Six bundled skills are installed. It is a development instruction plugin, not an app dependency or a way to increase account limits.

Installed path: `C:/Users/Aryan/.codex/plugins/cache/ponytail/ponytail/5.3.3`. The installed lifecycle manifest contains SessionStart, SubagentStart and UserPromptSubmit hooks. Installation/enabling does not establish hook trust; review them through Codex `/hooks` before trusting, and reload/restart into a new session to pick up the plugin. The current chat can follow the skill instructions directly, but that is not proof automatic hooks ran. No hook-trust records were edited or bypassed.

The plugin has no guaranteed token-savings percentage for Linqo. Prefer necessary changes, existing libraries and bounded verification, while preserving security, data-loss protection, accessibility and requested scope. The Claude-only usage band is not claimed to work in Codex. Project milestone backups contain this setup record, not the external global plugin installation.
