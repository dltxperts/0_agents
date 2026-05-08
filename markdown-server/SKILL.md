---
name: mdurl
description: Publish a local markdown file via the u3775 mdurl server and return a shareable URL. Use when the user asks to view a markdown doc in browser, share a plan, post a research note, or get a link to a file. Auto-invokes on "open in browser", "give me a link", "share this", "по ссылке", "в браузере". The CLI is `mdurl <path>`. The server lives at http://u3775:6420.
---

# mdurl — publish markdown for browser viewing

Tiny tool on u3775 that takes a local `.md` path and returns a Tailscale URL where the rendered document (dark theme + mermaid diagrams) is served.

## Auto-invoke when the user

- asks to "open this markdown in browser" / "show this plan" / "view as a page"
- says "give me a link to <some>.md"
- says "share this doc / report / research"
- uses Russian: "по ссылке", "в браузере", "открой в браузере", "ссылку на этот файл"
- types `/mdurl <path>` explicitly

Skip when:

- the user is not on Tailscale (URL won't be reachable)
- the file is not `.md` / `.markdown`
- the file does not exist on this host

## How it works

```bash
mdurl /absolute/path/to/file.md
# -> http://u3775:6420/<user>/<filename-without-ext>
```

Custom slug:

```bash
mdurl /path/to/file.md custom-slug
# -> http://u3775:6420/<user>/custom-slug
```

The CLI **copies** the file (does not symlink), so live updates require re-running `mdurl` after edits. This is the right trade-off: home-dir permissions (mode 750) prevent the service user from following symlinks into other users' homes.

## Other commands

```
mdurl -l               # list YOUR documents
mdurl -L               # list ALL documents (every user on this host)
mdurl -r <slug>        # remove one of YOUR documents
```

## Workflow when the user asks to publish

1. Resolve the markdown path (use absolute paths when ambiguous).
2. Run `mdurl <path>` (or `mdurl <path> <slug>` if the user wants a custom one).
3. Capture stdout (one line: the URL).
4. Reply with the URL: `http://u3775:6420/<user>/<slug>`.
5. If the URL fails to load:
   - check `systemctl is-active markdown-server` (or ask the user to)
   - check `mdurl -l` to confirm the file is registered
   - `journalctl -u markdown-server.service -n 30` for renderer errors

## When the CLI is missing

If `command -v mdurl` returns nothing, the package isn't installed on this host. Tell the user:

> The mdurl package is missing on this machine. Install it once with:
> ```bash
> sudo bash ~/Coding/0_agents/markdown-server/install.sh
> ```

Don't try to install it yourself unless the user explicitly approves — it touches /usr/local/bin and creates a system user.

## Don't

- Don't start your own grip / Python server in a one-off shell. Use the existing `mdurl` CLI.
- Don't `cp` directly into `/srv/markdown/` — let `mdurl` handle namespacing, slug sanitization, and URL printing.
- Don't `mdurl -r` someone else's slug — the CLI guards against it, but don't try.
- Don't push files containing secrets through `mdurl`. Anyone in the Tailscale tailnet can read by URL.
