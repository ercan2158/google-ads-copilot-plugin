# ads-copilot

Claude Code plugin for AI-driven Google Ads operations. One operator, one or
many SaaS apps. The AI is the expert; you type slash commands.

## Install

```bash
bin/install
```

This symlinks the plugin into `~/.claude/plugins/ads-copilot/` and runs a
one-shot Composio smoke test to verify connectivity.

## First run

```bash
cd ~/dev/personal/<your-app>     # any folder with a workspace.json
claude
> /ads-daily
```

The plugin walks up from cwd, finds `workspace.json`, and binds to that
account for the session.

## Commands

`/ads-daily`, `/ads-weekly`, `/ads-monthly`, `/ads-search-terms`,
`/ads-budgets`, `/ads-creative`, `/ads-bootstrap`, `/ads-explain`,
`/ads-apply <proposal-id>`. See `commands/` for what each does.

## Safety

`/ads-apply` is the only command that mutates the account. Everything else
is read-only or writes a proposal file you review before shipping.
