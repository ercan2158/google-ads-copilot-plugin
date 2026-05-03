# ads-copilot

Claude Code plugin for AI-driven Google Ads operations. One operator, one or
many SaaS apps. The AI is the expert; you type slash commands.

## One-time setup

1. **Create an OAuth 2.0 Desktop client** in Google Cloud Console, in the
   *same* Cloud project where your Google Ads developer token is approved.
   Add yourself as a **test user** under the OAuth consent screen.
2. **Write `~/.config/secrets/google-ads/credentials`** (chmod 600), with:
   ```
   DEVELOPER_TOKEN=<from Google Ads API Center>
   CLIENT_ID=<from your OAuth client>
   CLIENT_SECRET=<same OAuth client>
   ```
3. **Run `bin/oauth-bootstrap`** — opens the consent screen, captures the
   refresh token via a localhost listener on port 8765, appends
   `REFRESH_TOKEN=…` to the secrets file.
4. **Run `bin/install`** — runs unit tests, registers the plugin with Claude
   Code as a local marketplace, installs it, and pings
   `/v23/customers:listAccessibleCustomers` as a live smoke test.
5. **Restart Claude Code.**

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

## Token expiry note

If your OAuth consent screen is in **Testing** mode (the default for
unverified clients with restricted scopes like `adwords`), the refresh
token expires every 7 days. When `bin/install` reports an OAuth refresh
error, just re-run `bin/oauth-bootstrap`. To remove this constraint long
term, submit the OAuth client for Google's verification — separate
multi-week process.
