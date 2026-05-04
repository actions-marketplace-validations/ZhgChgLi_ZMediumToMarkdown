# ZMediumToMarkdown

![ZMediumToMarkdown](https://user-images.githubusercontent.com/33706588/184416147-c2ec74d4-7107-484e-8ad2-302340cf6c1f.png)

Download Medium posts and convert them to Markdown — for static blog import, automatic backups, or one-off scraping.

[![Gem](https://badge.fury.io/rb/ZMediumToMarkdown.svg)](https://rubygems.org/gems/ZMediumToMarkdown)
&nbsp;[中文介紹](https://medium.com/zrealm-ios-dev/converting-medium-posts-to-markdown-ddd88a84e177)

```bash
gem install ZMediumToMarkdown
ZMediumToMarkdown -p "https://medium.com/<USER>/<POST>" -s "$MEDIUM_COOKIE_SID" -d "$MEDIUM_COOKIE_UID"
```

> ⚠ **Strongly recommended: provide your Medium login cookies.**
> Medium fronts its API with Cloudflare and frequently blocks unauthenticated traffic — especially from cloud runners (GitHub Actions, Docker hosts, datacenter IPs). Without cookies you may get partial output, an HTTP 403 “Just a moment...” block, or paywalled content trimmed to its preview. See [Cookie setup](#cookie-setup) below.

---

## Features

- Download a single post, or every post by a Medium username
- Full Medium markup support: headings, blockquotes, lists, inline code, code fences with language, images (downloaded locally), embedded gists (rewritten to fenced code), tweets (rendered as blockquotes via the public syndication endpoint), YouTube cards, generic OG-image embeds
- Paywalled posts supported when authenticated cookies are provided
- Jekyll-friendly mode (front matter, `_posts/` layout, asset paths, `{:target="_blank"}` link markers)
- Skip-already-downloaded based on `last_modified_at` so it’s safe to run on a cron
- Multilingual: CJK / Arabic / Hebrew / Cyrillic / emoji all round-trip cleanly
- Ships as a gem and as a Docker image; usable from a GitHub Actions workflow

---

## Cookie setup

Medium’s GraphQL endpoint is behind Cloudflare’s bot management. Without a logged-in cookie, two things happen:

1. **Cloudflare may reject the request** with an HTTP 403 “Just a moment…” challenge page. Cloud-based runners (GitHub Actions, datacenter IPs, headless browsers) are particularly prone to this.
2. **Paywalled posts come back with `isLockedPreviewOnly: true`** and only the public preview text is returned by Medium — no amount of retries fixes that without authentication.

This tool detects both situations and prints actionable guidance, but it’s much easier to just provide cookies up front.

### How to get your `sid` and `uid`

1. Open <https://medium.com> in a browser, logged in to your account.
2. Open DevTools → **Application** (Chrome) or **Storage** (Firefox/Safari) → **Cookies** → `https://medium.com`.
3. Copy the values of the `sid` and `uid` cookies.

> Cookies expire roughly every two weeks — if downloads stop working, refresh them.

### Pass cookies to the CLI

Either as flags:

```bash
ZMediumToMarkdown -p "https://medium.com/..." \
                  -s "<your sid>" \
                  -d "<your uid>"
```

…or via environment variables (preferred — keeps secrets out of shell history):

```bash
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -p "https://medium.com/..."
```

CLI flags take precedence over environment variables.

### Still blocked by Cloudflare?

If even authenticated requests get challenged (typical when running from a datacenter IP), the most reliable workaround is to proxy traffic through a Cloudflare Worker so the request originates from inside Cloudflare’s own network. Walkthrough and complete GraphQL operation reference here:

> [Medium API 爬取資料與突破 Cloudflare 防護｜完整 GraphQL 操作教學](https://zhgchg.li/posts/zrealm-dev/medium-api-%E7%88%AC%E5%8F%96%E8%B3%87%E6%96%99%E8%88%87%E7%AA%81%E7%A0%B4-cloudflare-%E9%98%B2%E8%AD%B7-%E5%AE%8C%E6%95%B4-graphql-%E6%93%8D%E4%BD%9C%E6%95%99%E5%AD%B8-88f0fb935120/)

You can point the tool at your proxy via env vars:

| Variable | Default | Purpose |
|---|---|---|
| `MEDIUM_HOST` | `https://medium.com/_/graphql` | GraphQL endpoint |
| `MIRO_MEDIUM_HOST` | `https://miro.medium.com` | Image CDN |
| `TWITTER_SYNDICATION_HOST` | `https://cdn.syndication.twitter.com` | Tweet embed source |

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

# With cookies (paywall + Cloudflare workaround)
ZMediumToMarkdown -u zhgchgli -s "$MEDIUM_COOKIE_SID" -d "$MEDIUM_COOKIE_UID"
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

- **One-click Jekyll backup**: <https://github.com/ZhgChgLi/medium-to-jekyll-starter.github.io>
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
        with:
          command: "-u zhgchgli -s ${{ secrets.MEDIUM_COOKIE_SID }} -d ${{ secrets.MEDIUM_COOKIE_UID }}"
```

Store `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID` as repository secrets — never commit them.

---

## Example output

- [Original post on Medium](https://medium.com/zrealm-ios-dev/avplayer-%E5%AF%A6%E8%B8%90%E6%9C%AC%E5%9C%B0-cache-%E5%8A%9F%E8%83%BD%E5%A4%A7%E5%85%A8-6ce488898003)
- [Converted Markdown output](example/2021-01-31-avplayer-實踐本地-cache-功能大全-6ce488898003.md)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Unauthenticated request, or your IP is on Cloudflare’s bot list | Provide cookies (`-s` / `-d` or env vars). If the IP itself is the problem, proxy via a Cloudflare Worker — see [the article](#still-blocked-by-cloudflare). |
| `This post is behind Medium's paywall…` even though I set cookies | Cookies don’t belong to a Medium **Member** account, or they’ve expired (~2 weeks) | Refresh `sid` / `uid` from a logged-in browser; verify the account has access to the post. |
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
