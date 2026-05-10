# Privacy Notice

**ZMediumToMarkdown · Privacy `v1`** — what this CLI does and does not collect.

This Notice covers only the `ZMediumToMarkdown` Ruby gem (the **"Software"**). It does not cover Medium, GitHub, RubyGems, Cloudflare, or any other third-party service the Software contacts on your behalf — those services have their own privacy policies, and you are bound by them when you choose to interact with them.

## 1. Scope

The Software runs entirely on **your** machine, executed by **your** Ruby interpreter, under **your** user account. The Author has no server, no analytics endpoint, no telemetry channel, and receives **no data** from your runs.

## 2. What the Software does NOT collect

- **No analytics.** The Software does not phone home, does not record runs, does not measure usage, and does not generate any kind of identifier that could be sent to the Author.
- **No telemetry.** No crash reports, no performance metrics, no anonymous statistics.
- **No transmission of article content.** The Markdown the Software produces is written to your local filesystem (or your terminal in `--stdout` mode) and is never uploaded to anywhere by the Software.
- **No transmission of cookies to third parties.** Your Medium cookies (`sid`, `uid`, `cf_clearance`, `_cfuvid`) are sent **only** to `medium.com` itself, exactly as they would be in a normal browser request.

## 3. Local data the Software stores

| Path | What it is | When it is written |
|---|---|---|
| `~/.zmediumtomarkdown/cookies.json` (or similar) | AES-256-GCM encrypted cache of your Medium cookies. The encryption key is derived per machine; the file is readable only by your user account. | When you supply cookies via CLI flags / env vars / `--auth`. |
| `~/.zmediumtomarkdown/.tos-v1-accepted` | Plain-text marker recording the ISO-8601 timestamp of your first-run consent and the `Terms` version. | When you type `yes` at the first-run prompt or pass `--accept-terms`. |
| Output directory under your `cwd` | Markdown files and downloaded images. | Whenever you invoke a download (`-p` / `-u`, no `--stdout`). |

You can delete any of these at any time. Removing the `.tos-vN-accepted` file restarts the consent prompt on the next run.

## 4. Network calls the Software makes

When you invoke a download or render command, the Software contacts the following hosts. None of these calls are visible to the Author; they go directly from your machine to the listed hosts.

| Host | Purpose | Cookies attached |
|---|---|---|
| `medium.com/_/graphql` | Fetch post metadata + body via Medium's internal GraphQL endpoint. | Yes — your `sid` / `uid` / `cf_clearance` / `_cfuvid`. |
| `miro.medium.com/<imageId>` | Download article images. | No (Medium's image CDN does not require auth). |
| `cdn.syndication.twitter.com` | Expand embedded tweets into a Markdown blockquote (best-effort). | No. |
| `gist.github.com` / `gist.githubusercontent.com` | Expand embedded GitHub Gists into Markdown code blocks. | No. |
| `api.github.com/repos/ZhgChgLi/ZMediumToMarkdown/releases` | Check whether a newer gem version is available; printed as a one-line nudge. | No. |

If you configure a Cloudflare Worker proxy via `MEDIUM_HOST` (the `--medium_host` CLI flag), the GraphQL call is routed through that origin instead. **You** own and operate that Worker; its logging is governed by your Cloudflare account settings.

## 5. Cloudflare Worker proxy (optional)

If you deploy the optional Cloudflare Worker proxy described in [`wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy.md`](./wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy.md), Cloudflare may log request metadata (timestamps, IPs, headers) to your Cloudflare account dashboard per its default behavior. The Author does not have access to that data. Configure retention and logging on your own Cloudflare side.

## 6. Children's privacy

The Software is not directed at children under the age of thirteen (13). The Author does not knowingly collect any data from anyone, but the Software's intended users are adults capable of agreeing to its [Terms of Use](./TERMS.md).

## 7. Changes to this Notice

Material changes are signaled by bumping the `Privacy` version string in this document and in `lib/Terms.rb`. The CLI will surface the bump on the next run.

## 8. Contact

Questions about this Notice: GitHub Issues at [https://github.com/ZhgChgLi/ZMediumToMarkdown/issues](https://github.com/ZhgChgLi/ZMediumToMarkdown/issues).

---

**Last updated:** 2026-05-10
**Version:** `v1`
