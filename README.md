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

For **paywalled posts**, **bulk downloads**, or **CI / GitHub Actions**, configure Medium cookies. For CI and datacenter IPs, also use a Cloudflare Worker proxy. In practice, Medium may start blocking after about 10 posts without cookies, or about 25 posts from CI without a proxy.

> 📘 **[Setting Up Medium Cookies and a Cloudflare Worker Proxy →](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy)**

---

## Features

- Convert one Medium post or download every post from a Medium username.
- Preserve headings, blockquotes, lists, inline code, fenced code blocks, images, links, and front matter.
- Render common embeds: GitHub Gists, Twitter / X, YouTube, Vimeo, SoundCloud, Spotify, and generic OG-image cards.
- Download images locally and emit paths for either plain Markdown output or Jekyll projects.
- Read paywalled posts when valid Medium `sid` / `uid` cookies are provided.
- Skip unchanged posts by comparing `last_modified_at`, making scheduled backups practical.
- Keep multilingual text stable, including CJK, Arabic, Hebrew, Cyrillic, and emoji.
- Stream rendered Markdown to stdout for embedding callers (e.g. [mcp-medium-reader](https://github.com/ZhgChgLi/mcp-medium-reader)) via `--stdout` / `--list`, no filesystem writes.
- Run as a Ruby gem, local CLI tool, or GitHub Action.

---

## Cookies & Cloudflare setup

Medium's GraphQL endpoint is protected by Cloudflare. Two separate issues can interrupt a run:

1. **Cloudflare blocks the request** with an HTTP 403 "Just a moment…" challenge.
2. **Paywalled posts** come back with `isLockedPreviewOnly: true` — only the public preview is returned without authentication.

The right setup depends on what you are downloading and where the command runs:

| Scenario | Cookies (`sid` / `uid`) | Cloudflare Worker proxy |
|---|---|---|
| **CI / CD** (GitHub Actions, cloud runners) | **Strongly recommended** | **Strongly recommended** |
| **Local machine** (your laptop / desktop) | Recommended for paywalled posts | Optional |
| **Anything that downloads paywalled posts** | **Required** | (independent) |

**Empirical limits**: Medium may block after about 10 posts without cookies, or about 25 posts from CI / datacenter IPs without a Worker proxy. Configure both for scheduled backups.

**Local machine — manual challenge clearance.** If Cloudflare challenges a local run, open <https://medium.com> in your browser, complete the challenge, then run the command again. CI runners cannot clear browser challenges this way, so a Worker proxy is the practical option there.

### Quick start

Pass cookies through environment variables to keep secrets out of shell history:

```bash
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -p "https://medium.com/..."
```

Or pass them as flags for one-off runs. CLI flags take precedence over environment variables:

```bash
ZMediumToMarkdown -p "https://medium.com/..." -s "<your sid>" -d "<your uid>"
```

To use a Cloudflare Worker proxy, point the GraphQL and image endpoints at your Worker URLs:

| Variable | Default | Purpose |
|---|---|---|
| `MEDIUM_HOST` | `https://medium.com/_/graphql` | GraphQL endpoint |
| `MIRO_MEDIUM_HOST` | `https://miro.medium.com` | Image CDN |

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
  -x, --medium_host URL            Cloudflare Worker proxy URL (or $MEDIUM_HOST). Strongly
                                   recommended for CI / bulk runs — see the wiki setup guide.
      --miro_medium_host URL       Image-CDN proxy URL (or $MIRO_MEDIUM_HOST). Optional companion to -x.
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

# With cookies for paywalled posts or bulk downloads.
# Env vars keep secrets out of shell history and `ps` output.
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -u zhgchgli

# With a Cloudflare Worker proxy, recommended for CI and bulk runs.
ZMediumToMarkdown -u zhgchgli \
  -x "https://my-worker.my-account.workers.dev/_/graphql"
# …or via env: MEDIUM_HOST=https://my-worker.my-account.workers.dev/_/graphql
```

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
- **No image downloads** — image references stay as remote `miro.medium.com` URLs (or `MIRO_MEDIUM_HOST` proxy if set).
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
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Cloudflare bot challenge; common after about 10 posts without cookies, or about 25 posts from CI / datacenter IPs without a Worker proxy | **Local**: open <https://medium.com> in a browser, complete the challenge, then rerun. **CI / datacenter**: set up cookies and a Cloudflare Worker proxy; see the [setup guide](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy). |
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
