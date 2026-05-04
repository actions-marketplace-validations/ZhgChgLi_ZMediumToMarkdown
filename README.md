# ZMediumToMarkdown

![ZMediumToMarkdown](https://user-images.githubusercontent.com/33706588/184416147-c2ec74d4-7107-484e-8ad2-302340cf6c1f.png)

**Download Medium posts and convert them to Markdown** — for static blog import (Jekyll, Hugo, etc.), automatic GitHub Actions backups, or one-off scraping. Full markup, embedded images, gists, tweets, YouTube / Vimeo / SoundCloud / Spotify, paywalled posts (with cookies), CJK / Arabic / Hebrew / emoji all round-trip cleanly.

[![Gem](https://badge.fury.io/rb/ZMediumToMarkdown.svg)](https://rubygems.org/gems/ZMediumToMarkdown)

## Try it in 30 seconds

```bash
gem install ZMediumToMarkdown
ZMediumToMarkdown -p "https://medium.com/<USER>/<POST>"
```

That's it — the converted Markdown lands in `./Output/zmediumtomarkdown/`. No cookies needed for a public post.

For **paywalled posts**, **bulk downloads**, or running on **CI / GitHub Actions**, you'll want to add cookies and (for CI) a Cloudflare Worker proxy. Empirically: Cloudflare blocks after ~10 posts without cookies, or ~25 posts from CI / datacenter IPs without a Worker proxy. Full step-by-step guide:

> 📘 **[Setting Up Medium Cookies and a Cloudflare Worker Proxy →](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy)**

---

## Features

- Download a single post, or every post by a Medium username
- Full Medium markup support: headings, blockquotes, lists, inline code, code fences with language, images (downloaded locally), embedded gists (rewritten to fenced code), tweets (rendered as blockquotes via the public syndication endpoint — supports both `twitter.com` and `x.com`), YouTube / Vimeo / SoundCloud / Spotify embeds (Jekyll mode emits player iframes; plain mode renders local-thumbnail cards), generic OG-image embeds for everything else
- Paywalled posts supported when authenticated cookies are provided
- Jekyll-friendly mode (front matter, `_posts/` layout, asset paths, `{:target="_blank"}` link markers)
- Skip-already-downloaded based on `last_modified_at` so it’s safe to run on a cron
- Multilingual: CJK / Arabic / Hebrew / Cyrillic / emoji all round-trip cleanly
- Ships as a gem and as a Docker image; usable from a GitHub Actions workflow

---

## Cookies & Cloudflare setup

Medium's GraphQL endpoint sits behind Cloudflare's bot management. Two things can stop a run:

1. **Cloudflare blocks the request** with an HTTP 403 "Just a moment…" challenge.
2. **Paywalled posts** come back with `isLockedPreviewOnly: true` — only the public preview is returned without authentication.

The right setup depends on where you're running:

| Scenario | Cookies (`sid` / `uid`) | Cloudflare Worker proxy |
|---|---|---|
| **CI / CD** (GitHub Actions, Docker, cloud runners) | **Strongly recommended** | **Strongly recommended** |
| **Local machine** (your laptop / desktop) | Recommended for paywalled posts | Optional |
| **Anything that downloads paywalled posts** | **Required** | (independent) |

**Empirical limits**: ~10 posts without cookies, ~25 posts without a Worker proxy from CI / datacenter IPs, before Cloudflare blocks you. With both configured, scheduled jobs run reliably indefinitely.

**Local machine — manual challenge clearance.** If you only run on your own laptop, the simplest fix when Cloudflare throws a challenge is to open <https://medium.com> in a normal browser, complete the challenge yourself, then re-run — your residential IP will be cleared for a while. CI runners can't do this, which is why the Worker proxy is the only practical answer there.

### Quick start

Pass cookies via env vars (preferred — keeps secrets out of shell history):

```bash
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -p "https://medium.com/..."
```

…or as flags (fine for one-off runs; CLI flags take precedence over env vars):

```bash
ZMediumToMarkdown -p "https://medium.com/..." -s "<your sid>" -d "<your uid>"
```

To proxy through a Cloudflare Worker, point the tool at your Worker URL:

| Variable | Default | Purpose |
|---|---|---|
| `MEDIUM_HOST` | `https://medium.com/_/graphql` | GraphQL endpoint |
| `MIRO_MEDIUM_HOST` | `https://miro.medium.com` | Image CDN |
| `TWITTER_SYNDICATION_HOST` | `https://cdn.syndication.twitter.com` | Tweet embed source |

### Full setup guide

Step-by-step instructions for obtaining cookies and deploying a Cloudflare Worker proxy (with a copy-pasteable starter script):

> **[Setting Up Medium Cookies and a Cloudflare Worker Proxy](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy)** — covers both pieces end-to-end, including security notes (`sid` / `uid` are session tokens — treat them as secrets) and GitHub Actions wiring with `env:` blocks.

---

## Installation

### Gem (recommended)

```bash
gem install ZMediumToMarkdown
```

If you’re on macOS, prefer a managed Ruby (`rbenv` / `rvm` / `asdf`) over the system Ruby — `gem install` against `/usr/bin/ruby` requires `sudo` and pollutes the OS.

### From source

```bash
git clone https://github.com/ZhgChgLi/ZMediumToMarkdown
cd ZMediumToMarkdown
bundle install
bundle exec ruby bin/ZMediumToMarkdown -p "https://medium.com/..."
```

### Docker

```bash
docker build -t zmediumtomarkdown:latest \
  --build-arg CRON_SETTING="0 8 * * *" \
  --build-arg ZMEDIUMTOMARKDOWN_COMMAND="-u <username> -s $MEDIUM_COOKIE_SID -d $MEDIUM_COOKIE_UID" \
  .
docker run -v "$(pwd)":/usr/src/app zmediumtomarkdown
```

The image runs `cron` so the configured command repeats on the schedule you pass in. Output is written to the mounted volume.

---

## Usage

```
ZMediumToMarkdown [options]

  -s, --cookie_sid SID             Medium logged-in cookie sid (or $MEDIUM_COOKIE_SID)
  -d, --cookie_uid UID             Medium logged-in cookie uid (or $MEDIUM_COOKIE_UID)
  -u, --username USERNAME          Download every post by a Medium username
  -p, --postURL POST_URL           Download a single post URL
      --jekyll                     Emit Jekyll-friendly output (combine with -u or -p)
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

# With cookies (paywall + bulk download). Prefer env vars over -s / -d
# flags so the values don't end up in shell history or `ps` output.
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -u zhgchgli
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

Store `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID` as repository **secrets** (encrypted, masked from logs) — not repository variables, and never hard-coded in the YAML. Pass them via the step's `env:` block as shown rather than inside the `command:` string, so the values never appear in run logs. For CI runs we strongly recommend also pointing `MEDIUM_HOST` at a Cloudflare Worker proxy — see the [setup guide](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy).

---

## Example output

- [Original post on Medium](https://medium.com/zrealm-ios-dev/avplayer-%E5%AF%A6%E8%B8%90%E6%9C%AC%E5%9C%B0-cache-%E5%8A%9F%E8%83%BD%E5%A4%A7%E5%85%A8-6ce488898003)
- [Converted Markdown output](example/2021-01-31-avplayer-實踐本地-cache-功能大全-6ce488898003.md)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Cloudflare bot challenge — common after ~10 posts without cookies, ~25 from CI / datacenter IPs without a Worker proxy | **Local**: open <https://medium.com> in a browser, complete the challenge, re-run. **CI / datacenter**: set up cookies + a Cloudflare Worker proxy — see the [setup guide](https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy). |
| `This post is behind Medium's paywall…` even though I set cookies | Cookies don’t belong to a Medium **Member** account that can read this post, or they’ve expired (~2 weeks of inactivity) | Refresh `sid` / `uid` from a logged-in browser; verify the account has access to the post. Cookies stay valid as long as they keep being used. |
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
