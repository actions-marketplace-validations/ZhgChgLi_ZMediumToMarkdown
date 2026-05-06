# ZMediumToMarkdown

![ZMediumToMarkdown](https://user-images.githubusercontent.com/33706588/184416147-c2ec74d4-7107-484e-8ad2-302340cf6c1f.png)

Download Medium posts as clean Markdown, preserving structure, images, links, code blocks, and common embeds for plain Markdown or Jekyll workflows.

[![Gem](https://badge.fury.io/rb/ZMediumToMarkdown.svg)](https://rubygems.org/gems/ZMediumToMarkdown)

## Try it in 30 seconds

```bash
gem install ZMediumToMarkdown
ZMediumToMarkdown -p "https://medium.com/<USER>/<POST>"
```

The converted Markdown is written to `./Output/zmediumtomarkdown/`. Public posts usually work without cookies.

For **paywalled posts**, **bulk downloads**, or **CI / GitHub Actions**, you'll need Medium login cookies. On a local TTY the tool can auto-capture them by opening Chrome the first time Cloudflare blocks; CI runs need a Cloudflare Worker proxy. See [Cookies & Cloudflare setup](#cookies--cloudflare-setup).

> 📘 **[Setting Up Medium Cookies and a Cloudflare Worker Proxy →](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy)**

---

## Features

- Convert one Medium post or download every post from a Medium username.
- Preserve headings, blockquotes, lists, inline code, fenced code blocks, images, links, and front matter.
- Render common embeds: GitHub Gists, Twitter / X, YouTube, Vimeo, SoundCloud, Spotify, and generic OG-image cards.
- Download images locally and emit paths for either plain Markdown output or Jekyll projects.
- Read paywalled posts when valid Medium `sid` / `uid` cookies (Membership account) are provided.
- Auto-capture login cookies via Chrome on a local TTY when Cloudflare blocks, into an encrypted on-disk cache reused on subsequent runs.
- Skip unchanged posts by comparing `last_modified_at`, making scheduled backups practical.
- Keep multilingual text stable, including CJK, Arabic, Hebrew, Cyrillic, and emoji.
- Stream rendered Markdown to stdout for embedding callers (e.g. [mcp-medium-reader](https://github.com/ZhgChgLi/mcp-medium-reader)) via `--stdout` / `--list`, no filesystem writes.
- Run as a Ruby gem, local CLI tool, or GitHub Action.

---

## Cookies & Cloudflare setup

Medium's GraphQL endpoint is protected by Cloudflare. Two failure modes interrupt a run:

1. **Cloudflare bot challenge** — HTTP 403 / "Just a moment…". Empirically: after ~10 posts without cookies, or ~25 posts from CI / datacenter IPs without a Worker proxy.
2. **Paywalled posts** — return only the public preview unless `sid` / `uid` come from a logged-in Medium **Member** account.

### What you need by scenario

| Scenario | `sid` / `uid` cookies | Cloudflare Worker proxy |
|---|---|---|
| CI / CD (GitHub Actions, cloud runners) | **Strongly recommended** | **Strongly recommended** |
| Local machine (laptop / desktop) | Recommended for paywalled posts | Optional |
| Paywalled posts (anywhere) | **Required** (Membership account) | Independent |

### Three ways to clear a Cloudflare block

1. **Auto-login on a TTY (local).** When Cloudflare blocks an interactive run and Google Chrome is installed, the tool opens Chrome at <https://medium.com>; sign in / clear the challenge, and `sid` / `uid` / `cf_clearance` / `_cfuvid` are captured into an AES-256-GCM-encrypted cache at `~/.zmediumtomarkdown` (chmod 0600). Cached cookies are reused on subsequent runs and refreshed on every new block, so you rarely repeat the flow. Run `ZMediumToMarkdown --auth` once to trigger this flow on demand and seed the cache before any real run. Pass `--non-interactive` (or set `MEDIUM_NO_AUTO_BROWSER=1`) to suppress the prompt and fail fast.
2. **Cloudflare Worker proxy.** Permanent fix, recommended for CI. Point the GraphQL endpoint (and optionally the image CDN) at your own Worker so requests originate from inside Cloudflare's network instead of a flagged datacenter IP.
3. **Manual `cf_clearance` / `_cfuvid` cookies.** Short-term unblocking (~30 min). Useful when you can't run Chrome and don't want to set up a Worker proxy yet.

### Inputs

CLI flag wins over env var, env var wins over the on-disk cache.

| Cookie / variable | CLI flag | Env var |
|---|---|---|
| `sid` (Medium login) | `-s, --cookie_sid` | `MEDIUM_COOKIE_SID` |
| `uid` (Medium login) | `-d, --cookie_uid` | `MEDIUM_COOKIE_UID` |
| `cf_clearance` | `--cookie_cf_clearance` | `MEDIUM_COOKIE_CF_CLEARANCE` |
| `_cfuvid` | `--cookie_cfuvid` | `MEDIUM_COOKIE_CFUVID` |
| Worker proxy host | `-x, --medium_host` | `MEDIUM_HOST` (default `https://medium.com/_/graphql`). Covers both medium.com and miro.medium.com — the Worker dispatches by path. |
| Worker shared secret | — | `MEDIUM_HOST_SECRET` (sent as `X-Medium-Proxy-Secret` header on proxy requests; matches the `SECRET` constant in the Worker script) |

```bash
# Env-var form (preferred — keeps secrets out of shell history)
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -p "https://medium.com/..."

# Or as flags for one-off runs
ZMediumToMarkdown -p "https://medium.com/..." -s "<sid>" -d "<uid>"

# Behind a single Cloudflare Worker that handles both medium.com and miro.medium.com
export MEDIUM_HOST="https://my-worker.my-account.workers.dev/_/graphql"
export MEDIUM_HOST_SECRET="<your-secret>"
ZMediumToMarkdown -u zhgchgli
```

### Full setup guide

The setup guide covers cookie extraction, Cloudflare Worker deployment, security notes, and GitHub Actions wiring:

> **[Setting Up Medium Cookies and a Cloudflare Worker Proxy](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy)**

---

## Installation

### Gem (recommended)

```bash
gem install ZMediumToMarkdown
```

On macOS, prefer a managed Ruby (`rbenv` / `rvm` / `asdf`) over the system Ruby. Installing gems against `/usr/bin/ruby` usually requires `sudo` and modifies the OS Ruby environment.

### From source

```bash
git clone https://github.com/ZhgChgLi/ZMediumToMarkdown
cd ZMediumToMarkdown
bundle install
bundle exec ruby bin/ZMediumToMarkdown -p "https://medium.com/..."
```

---

## Usage

```
ZMediumToMarkdown [options]

  -s, --cookie_sid SID             Medium logged-in cookie sid (or $MEDIUM_COOKIE_SID)
  -d, --cookie_uid UID             Medium logged-in cookie uid (or $MEDIUM_COOKIE_UID)
      --cookie_cf_clearance VALUE  Cloudflare cf_clearance cookie (or $MEDIUM_COOKIE_CF_CLEARANCE).
                                   Short-term Cloudflare unblocking; expires ~30 min.
      --cookie_cfuvid VALUE        Cloudflare _cfuvid cookie (or $MEDIUM_COOKIE_CFUVID).
                                   Companion to cf_clearance.
  -x, --medium_host URL            Cloudflare Worker proxy URL (or $MEDIUM_HOST). One Worker
                                   covers both medium.com and miro.medium.com via path
                                   dispatch. Set $MEDIUM_HOST_SECRET to the same secret used
                                   in the Worker script. Strongly recommended for CI / bulk
                                   runs — see the wiki setup guide.
      --non-interactive            Never prompt or open Chrome on a Cloudflare block. CI runners
                                   auto-detect this; use the flag to force the same behavior on a TTY.
      --auth                       Open Chrome to sign in, capture cookies into the encrypted
                                   cache (~/.zmediumtomarkdown), and exit. Run once before bulk /
                                   scheduled jobs to seed the cache up front.
  -u, --username USERNAME          Download every post by a Medium username
  -p, --postURL POST_URL           Download a single post URL
      --jekyll                     Emit Jekyll-friendly output (combine with -u or -p)
      --stdout                     Render Markdown to stdout; skip all image/asset downloads.
                                   Use with -p or -u. Logs and banners go to stderr.
      --list                       With -u, emit one NDJSON line per post (title, url, dates,
                                   tags, etc.) to stdout. Skips bodies and image downloads.
      --limit N                    Cap the number of posts processed by -u in --stdout / --list.
  -n, --new                        Update to the latest version (gem install only)
  -c, --clean                      Remove every downloaded post under cwd
  -v, --version                    Print the current version
  -h, --help                       Show this message
```

### Examples

```bash
# Single post into ./Output/zmediumtomarkdown/
ZMediumToMarkdown -p "https://medium.com/<user>/<slug>-<id>"

# Every post by a user, Jekyll-friendly into ./_posts/zmediumtomarkdown/ + ./assets/
ZMediumToMarkdown -u zhgchgli --jekyll
```

For paywalled / bulk / CI runs, also pass cookies and (optionally) a Worker proxy — see [Cookies & Cloudflare setup](#cookies--cloudflare-setup).

> **Deprecated flags.** `-j USERNAME` and `-k POST_URL` still work for backwards compatibility but emit a warning. Use `--jekyll -u …` / `--jekyll -p …` instead.

### Output layout

| Mode | Markdown destination | Image destination |
|---|---|---|
| Plain (`-p` / `-u`) | `./Output/zmediumtomarkdown/<date>-<slug>.md` | `./Output/zmediumtomarkdown/assets/<post_id>/` |
| Jekyll (`--jekyll`) | `./_posts/zmediumtomarkdown/<date>-<post_id>.md` | `./assets/<post_id>/` |

When run with `-u`, plain mode additionally nests under `./Output/users/<username>/`.

Reruns are cheap — posts whose `last_modified_at` matches the existing front matter are skipped.

---

## Embedding callers — `--stdout` / `--list`

The gem can also be invoked as a backend for tools that need rendered Markdown without filesystem side effects — most notably the [`mcp-medium-reader`](https://github.com/ZhgChgLi/mcp-medium-reader) MCP server, which exposes Medium reading to LLMs.

In `--stdout` / `--list` mode:

- Markdown / NDJSON is written to **stdout**; banners, progress, and warnings go to **stderr**.
- **No filesystem writes**, no `Output/` directory, no `assets/` directory.
- **No image downloads** — image references stay as remote URLs on `miro.medium.com` (or your `MEDIUM_HOST` proxy origin when configured).
- Skip-already-downloaded checks are bypassed; the post is rendered fresh every time.

```bash
# Stream a single post's Markdown to stdout.
ZMediumToMarkdown --stdout -p "https://medium.com/<user>/<slug>-<id>"

# Stream every post by a user, separated by `\n\n---\n\n`. --limit caps the count.
ZMediumToMarkdown --stdout -u zhgchgli --limit 5

# List a user's posts as NDJSON (one JSON object per line). No bodies.
ZMediumToMarkdown --list -u zhgchgli --limit 20
# {"title":"…","url":"…","creator":"…","firstPublishedAt":"…","latestPublishedAt":"…","tags":["…"],"description":"…","pin":false}
```

Cookies and Worker-proxy env vars apply the same way as in normal mode.

---

## Quick-start templates

- **GitHub Actions backup, no code**: [How-to walkthrough](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/How-to-use-Github-Action-as-your-free-&-no-code-Medium-Posts-backup-service)
- **Working Action repo example**: <https://github.com/ZhgChgLi/ZMediumToMarkdown-github-action>

### Minimal GitHub Action

```yaml
name: ZMediumToMarkdown
on:
  workflow_dispatch:
  schedule:
    - cron: "10 1 15 * *" # 01:10 on day-of-month 15
jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - uses: ZhgChgLi/ZMediumToMarkdown@main
        env:
          MEDIUM_COOKIE_SID: ${{ secrets.MEDIUM_COOKIE_SID }}
          MEDIUM_COOKIE_UID: ${{ secrets.MEDIUM_COOKIE_UID }}
        with:
          command: "-u zhgchgli"
```

Store `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID` as repository **secrets**, not repository variables, and never hard-code them in YAML. Pass them through the step's `env:` block instead of the `command:` string so they stay out of logs. For CI, also point `MEDIUM_HOST` at a Cloudflare Worker proxy; see the [setup guide](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy).

---

## Example output

- [Original post on Medium](https://medium.com/zrealm-ios-dev/avplayer-%E5%AF%A6%E8%B8%90%E6%9C%AC%E5%9C%B0-cache-%E5%8A%9F%E8%83%BD%E5%A4%A7%E5%85%A8-6ce488898003)
- [Converted Markdown output](example/2021-01-31-avplayer-實踐本地-cache-功能大全-6ce488898003.md)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Cloudflare bot challenge; common after about 10 posts without cookies, or about 25 posts from CI / datacenter IPs without a Worker proxy | **Local**: on a TTY the tool auto-opens Chrome to clear the challenge and refresh cookies (cached at `~/.zmediumtomarkdown`). If Chrome is not installed, open <https://medium.com> in any browser, clear the challenge, then rerun. **CI / datacenter**: set up cookies and a Cloudflare Worker proxy — see the [setup guide](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy). |
| `This post is behind Medium's paywall…` even though I set cookies | Cookies do not belong to a Medium **Member** account that can read this post, or they have expired after inactivity | Refresh `sid` / `uid` from a logged-in browser and verify the account has access to the post. Cookies stay valid as long as they keep being used. |
| `Error: Too Many Requests, blocked by Medium` | Hit Medium’s rate limit | Slow the schedule down or split the run; the tool already retries up to 10 times. |
| Markdown looks fine but CJK / emoji is mojibaked | Older release — encoding regression | Upgrade to ≥ 2.6.7 (this release force-encodes all responses to UTF-8). |
| `An iframe came back blank` | Generic embed (non-Twitter, non-gist, non-YouTube, non-widgetic) without an OG image | Expected — the source has no image to embed. The tool emits an empty line so paragraph spacing is preserved. |

---

## Development

```bash
bundle install
bundle exec rake test         # run the minitest suite
```

The suite includes a 174-paragraph end-to-end fixture under `test/fixtures/`. To regenerate the golden Markdown file after intentional output changes:

```bash
UPDATE_FIXTURES=1 bundle exec rake test
```

CI runs the same `rake test` against Ruby 3.2 / 3.3 / 3.4.

---

## Disclaimer

All content downloaded using ZMediumToMarkdown — articles, images, video — is subject to copyright and belongs to its respective owner. This tool does not claim ownership of any downloaded content.

Downloading and using copyrighted content without the owner's permission may be illegal. ZMediumToMarkdown does not condone copyright infringement and will not be held responsible for misuse of this tool. Users are solely responsible for ensuring they have the necessary permissions and rights for any content they download.

By using ZMediumToMarkdown you acknowledge and agree to comply with all applicable copyright laws and regulations.

---

## Other works

**Swift libraries**
- [ZMarkupParser](https://github.com/ZhgChgLi/ZMarkupParser) — pure-Swift HTML → `NSAttributedString` with customizable style/tag mapping.
- [ZPlayerCacher](https://github.com/ZhgChgLi/ZPlayerCacher) — lightweight `AVAssetResourceLoaderDelegate` cache for `AVPlayerItem` streaming.

**Integration tools**
- [mcp-medium-reader](https://github.com/ZhgChgLi/mcp-medium-reader) — macOS MCP server that wraps this gem so LLMs (Claude Desktop, etc.) can read Medium posts.
- [XCFolder](https://github.com/ZhgChgLi/XCFolder) — convert Xcode virtual groups to real directories (Tuist / XcodeGen friendly).
- [ZReviewTender](https://github.com/ZhgChgLi/ZReviewTender) — fetch App Store / Google Play reviews into your workflow.
- [linkyee](https://github.com/ZhgChgLi/linkyee) — open-source LinkTree alternative on GitHub Pages.

---

## About

- <https://zhgchg.li/>
- <https://blog.zhgchg.li/>

## Donate

[![Buy Me A Beer](https://github.com/user-attachments/assets/63f01edf-2aa5-4d91-8f8a-861e5b6b4feb)](https://www.paypal.com/ncp/payment/CMALMPT8UUTY2)

If this project helped you, please star the repo or [buy me a beer](https://www.paypal.com/ncp/payment/CMALMPT8UUTY2). PRs and issue reports welcome.
