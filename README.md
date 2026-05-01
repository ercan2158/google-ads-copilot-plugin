# ads-copilot

Claude Code plugin for AI-driven Google Ads operations. One operator, one or
many SaaS apps. The AI is the expert; you type slash commands.

## One-time setup

1. **Create an OAuth 2.0 Desktop client** in Google Cloud Console, in the
   *same* Cloud project where your Google Ads developer token is approved.
2. **Write `~/.config/secrets/google-ads/credentials`** (one `KEY=value` per
   line, chmod 600):
   ```
   DEVELOPER_TOKEN=<from Google Ads API Center>
   CLIENT_ID=<from your OAuth client>
   CLIENT_SECRET=<same OAuth client>
   ```
3. **Run `bin/oauth-bootstrap`** — opens the consent screen, captures the
   refresh token via a localhost redirect, appends `REFRESH_TOKEN=…` to the
   secrets file.
4. **Run `bin/install`** — symlinks the plugin into Claude Code, runs unit
   tests, and pings `/v23/customers:listAccessibleCustomers` as a live
   smoke test. On success it prints the customer IDs you can access.

## Daily use

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
