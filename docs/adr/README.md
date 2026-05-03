# Architectural Decision Records (ADRs)

This folder captures the **original design and planning** of ads-copilot
as of 2026-04-30. These documents are **historical** — they record the
thinking at the time, not the current implementation. Some decisions have
since been revised (notably: the `~/.local/bin/ads-ga` symlink was dropped
in favor of calling the helper via `${CLAUDE_PLUGIN_ROOT}/bin/ga`, and the
Composio integration mentioned in the design doc was abandoned).

Treat these as primary-source context for **why** the plugin is shaped the
way it is. For up-to-date usage, see the top-level `README.md`.
