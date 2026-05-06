# Setting Up Medium Cookies and a Cloudflare Worker Proxy

Medium's GraphQL endpoint sits behind Cloudflare's bot management layer. Out of the box, two things tend to break unauthenticated runs:

1. **Cloudflare blocks the request** with an HTTP 403 "Just a moment…" challenge — particularly common from cloud runners (GitHub Actions, datacenter IPs, headless browsers).
2. **Paywalled posts** come back with `isLockedPreviewOnly: true` and only the public preview text is returned by Medium.

You have **three building blocks** to address these. They solve different problems and stack — pick what matches where you run:

- **Medium login cookies (`sid`, `uid`)** — unlock paywalled posts and authenticate as a Medium Member. Required for full content.
- **Cloudflare Worker proxy** — make requests originate from inside Cloudflare's network so datacenter IPs don't get bot-checked. Required for reliable runs from CI / Docker / cloud runners.
- **Auto-login on a local TTY (since v3.2.0)** — when Cloudflare blocks an interactive run, the tool can drive a real Chrome window for you, let you sign in / clear the challenge, and capture all four relevant cookies (`sid`, `uid`, `cf_clearance`, `_cfuvid`) into an encrypted cache for re-use. The easiest path on a laptop / desktop; not applicable to CI.

| Where you run | Recommended setup |
|---|---|
| Local laptop / desktop | Auto-login on Cloudflare block (Section 1a). Worker proxy optional. |
| CI / GitHub Actions / Docker / cloud runners | Manual cookies + Worker proxy with secret (Sections 1b + 2). Auto-login is unavailable here. |
| Anywhere downloading paywalled posts | Membership-account `sid` / `uid` (any extraction method). Worker proxy is independent. |

---

## 1. How to Get Your Medium Cookies

`ZMediumToMarkdown` consumes up to four cookies. The first two are session-level; the last two are Cloudflare bot-management cookies:

| Cookie | Issued by | Purpose | Lifespan |
|---|---|---|---|
| `sid` | Medium | Session token (logs you in) | ~2-week sliding window |
| `uid` | Medium | Account identifier | ~2-week sliding window |
| `cf_clearance` | Cloudflare | Marks this client as having passed a recent bot challenge | ~30 minutes |
| `_cfuvid` | Cloudflare | Companion to `cf_clearance` | session |

You don't normally have to think about `cf_clearance` / `_cfuvid` separately — the auto-login flow captures them along with `sid` / `uid`. Manual setting is only useful as a short-term unblock when you can't run Chrome and don't have a Worker proxy yet.

### 1a. Auto-login via Chrome (recommended for local TTY)

When Cloudflare blocks an interactive run and Google Chrome is installed, `ZMediumToMarkdown` opens a real Chrome window pointed at <https://medium.com>:

1. Sign in to your Medium account in that window (use the **Member** account if you want paywalled content).
2. Clear any "Just a moment…" challenge that comes up.
3. Come back to the terminal and press **Enter**.

The tool then reads `sid` / `uid` / `cf_clearance` / `_cfuvid` straight out of the browser, writes them to an encrypted cache, and retries the request. On every later block in the same process the flow re-runs to refresh cookies, so a long bulk download survives a `cf_clearance` expiring mid-run.

**Triggering it on demand.** You don't have to wait for a Cloudflare block — run `ZMediumToMarkdown --auth` once before kicking off bulk / scheduled work. It opens the same Chrome flow, captures the cookies, writes the cache, and exits. Useful right after installing the gem, switching machines, or signing in with a different account.

**Where the cache lives.** `~/.zmediumtomarkdown` (single file, not a directory). The contents are encrypted with AES-256-GCM and the file is `chmod 0600`. Subsequent runs auto-load from this cache, so you usually go through the Chrome flow at most once per machine. The path is overridable via `ZMEDIUM_COOKIE_CACHE_PATH` if you need to relocate it.

> **Security note on the cache encryption.** The encryption key is shipped in the gem source. This is obfuscation against casual filesystem snooping — anyone with both the cache file *and* the gem source can decrypt it. The 0600 permission is the real perimeter; do not place the cache on a shared filesystem.

**Suppressing the prompt.** If you don't want Chrome popping up on a TTY (for example you'd rather see the error and fix it manually, or you're embedding the CLI in something else), pass `--non-interactive` or set `MEDIUM_NO_AUTO_BROWSER=1`. CI / non-TTY environments are auto-detected and never prompt.

**Requirements.** Google Chrome (or a Chromium-based browser ferrum can detect) must be installed. If it isn't, the tool falls back to opening your default browser at <https://medium.com> and waiting for you to clear the challenge by hand — without auto-capturing cookies. In that case, follow Section 1b to extract them manually.

### 1b. Manual extraction via DevTools

Use this when you're on CI, when you can't install Chrome, or when you want to copy `sid` / `uid` once and inject them as secrets.

<img width="2082" height="975" alt="image" src="https://github.com/user-attachments/assets/32adc711-74eb-46ed-927a-60b1ccd66fbc" />


1. Open <https://medium.com> in a browser and **make sure you are logged in**. If you have a Member subscription, log in with the Member account so paywalled posts are accessible from this session.
2. Open DevTools:
    - **Chrome / Edge**: `View → Developer → Developer Tools` (or `F12`), then go to the **Application** tab.
    - **Firefox**: `Tools → Browser Tools → Web Developer Tools`, then go to the **Storage** tab.
    - **Safari**: enable the Develop menu (`Settings → Advanced → Show Develop menu`), then `Develop → Show Web Inspector`, and go to the **Storage** tab.
3. In the left-hand panel, expand **Cookies** and select `https://medium.com`.
4. Find the rows named `sid` and `uid` (and optionally `cf_clearance` / `_cfuvid` if you want a short-term Cloudflare unblock). Copy their **Value** column.

> **Cookie expiry & rotation.** Medium issues `sid` / `uid` with roughly a two-week sliding window. As long as the cookies keep being **used** (each successful request resets the clock), they stay valid indefinitely — so a daily or weekly scheduled job typically never needs to refresh them. They only expire when nothing has touched them for two weeks, after which Medium rotates the values and you'll need to copy fresh ones from a logged-in browser. `cf_clearance` is far shorter-lived (~30 minutes); don't bake it into long-lived secrets — let the auto-login flow refresh it, or rely on a Worker proxy instead.

> **⚠ Security — treat `sid` / `uid` like passwords.** These are not "preferences" or "settings"; they are **session tokens that fully authenticate as your Medium account**. Anyone who obtains them can read your paywalled content, post / clap / follow as you, and access your account-level information until you sign out. Treat them with the same care as an API key or a database password:
>
> - **Never commit them to a repository**, public or private. Use GitHub Actions secrets, CI environment variables, or a secrets manager.
> - **Never paste them into screenshots, gists, support tickets, or chat logs.** Even a redacted screenshot can leak metadata.
> - **Never share the value with anyone.** If you ever do, sign out of every Medium session immediately (Medium account → Settings → Security → "Sign out of all sessions") to invalidate them, then grab a fresh pair.
> - **Avoid passing them as CLI flags on shared machines** — flags show up in shell history and `ps` output. Prefer the `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID` environment variables.

### Passing cookies to the CLI

Cookie precedence is **CLI flag → env var → on-disk cache**, highest to lowest. Each layer fills only what the higher one left empty.

| Cookie | CLI flag | Env var |
|---|---|---|
| `sid` | `-s, --cookie_sid` | `MEDIUM_COOKIE_SID` |
| `uid` | `-d, --cookie_uid` | `MEDIUM_COOKIE_UID` |
| `cf_clearance` | `--cookie_cf_clearance` | `MEDIUM_COOKIE_CF_CLEARANCE` |
| `_cfuvid` | `--cookie_cfuvid` | `MEDIUM_COOKIE_CFUVID` |

**Via flags** (visible in shell history — fine for one-off local runs):

```bash
ZMediumToMarkdown -p "https://medium.com/<USER>/<POST>" \
                  -s "<your sid>" \
                  -d "<your uid>"
```

**Via environment variables** (preferred for CI / containers — keeps secrets out of shell history and process listings):

```bash
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"
ZMediumToMarkdown -p "https://medium.com/<USER>/<POST>"
```

In a GitHub Actions workflow, store them as **repository secrets** (`Settings → Secrets and variables → Actions → New repository secret`) and inject them into the step's environment — not into the `command` string:

```yaml
- uses: ZhgChgLi/ZMediumToMarkdown@main
  env:
    MEDIUM_COOKIE_SID: ${{ secrets.MEDIUM_COOKIE_SID }}
    MEDIUM_COOKIE_UID: ${{ secrets.MEDIUM_COOKIE_UID }}
  with:
    command: '-u zhgchgli'
```

The composite action propagates the step's `env:` block to its inner shell, and `ZMediumToMarkdown` picks the values up via `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID`. This keeps the cookie values out of the `command` string entirely.

> **Use repository secrets, not repository variables.** GitHub offers both *Secrets* and *Variables* under the same Actions settings page; only Secrets are encrypted and masked from logs. Variables are visible to anyone with read access to the repo. Always pick **Secrets** for `sid` / `uid`. Never hard-code the values into the YAML, and never commit them to a repository — public *or* private.

---

## 2. How to Set Up a Cloudflare Worker Proxy

### Why you need it

Even with valid cookies, Cloudflare's bot detection can challenge requests based on the source IP. **Datacenter and cloud-runner IPs** (AWS, GCP, GitHub-hosted runners, Docker hosts on shared cloud providers, etc.) are particularly likely to be flagged. Symptoms include:

- `Blocked by Medium's Cloudflare layer (HTTP 403)` errors.
- "Just a moment…" challenge HTML coming back instead of GraphQL JSON.
- Runs that work locally but fail in CI.

The most reliable workaround is to send your request through a tiny **Cloudflare Worker** that you deploy on your own free Cloudflare account. The Worker forwards your request to Medium from inside Cloudflare's network — so to Medium's edge, the request looks like it came from another Cloudflare service, not from a flagged datacenter IP. (The auto-login flow from Section 1a doesn't help here — CI doesn't have a TTY for someone to click through Chrome.)

### Architecture

```
ZMediumToMarkdown                 Your CF Worker                    upstream
─────────────────                 ──────────────                    ────────
  GraphQL POST /_/graphql ──┐                                       medium.com
  iframe GET  /media/<id>   │ + X-Medium-Proxy-Secret               medium.com
  OG     GET  /<user>/<post>├──►  <your-worker>.workers.dev  ──┬──► medium.com
  image  GET  /<filename>   │                                  └──► miro.medium.com
                            │                                      (path-pattern dispatch)
                            └──── response (proxied) ◄─────────
```

One Worker handles **both** medium.com and miro.medium.com. You set just `MEDIUM_HOST` (plus `MEDIUM_HOST_SECRET`) on the gem side — the gem auto-derives the miro host from `MEDIUM_HOST`'s origin. The Worker dispatches by path pattern (paths starting with `/v2/`, `/max/`, `/freeze/`, `/proxy/`, `/da/`, `/fit/`, or containing `*` go to miro.medium.com — everything else goes to medium.com).

The Worker is small (a few dozen lines of JavaScript) and stays well within Cloudflare's free tier for personal use.

### Setup walkthrough

1. Create a free Cloudflare account if you don't have one.
2. Go to **Workers & Pages → Create → Create Worker**, give it a non-guessable name (e.g. `medium-proxy-` plus a random suffix), and click **Deploy** to create the placeholder.
3. Click **Edit code** and paste in the script from [`worker_example.js`](worker_example.js). Replace the `SECRET` constant with your own random string (`openssl rand -base64 32` is a reasonable source).
4. Click **Deploy**. You'll get a URL like `https://<your-worker-name>.<your-account>.workers.dev`.
5. Test it (replace `<SECRET>` with the value you set in the script):

   ```bash
   curl -X POST "https://<your-worker-name>.<your-account>.workers.dev/_/graphql" \
     -H "Content-Type: application/json" \
     -H "X-Medium-Proxy-Secret: <SECRET>" \
     -d '[{"operationName":"PostViewerEdgeContentQuery","variables":{"postId":"abcdef123456"},"query":"..."}]'
   ```

   You should get a Medium GraphQL response. A request without the header (or with the wrong value) returns 403.

### Worker script

The full script is at [`worker_example.js`](worker_example.js). Highlights:

- **Auth via `X-Medium-Proxy-Secret` header.** Every request must carry the header matching the script's `SECRET` constant — anything else returns 403. The gem only sets this header when calling a configured custom proxy host, so the secret never leaks to upstream Medium. The header (and Cloudflare hop headers) are stripped from the forwarded request.
- **Path-pattern dispatch.** Paths starting with `/v2/`, `/max/`, `/freeze/`, `/proxy/`, `/da/`, `/fit/`, or containing `*` are forwarded to `https://miro.medium.com<path>`. Everything else is forwarded to `https://medium.com<path>`. medium.com slugs never contain `*` or those prefixes, so the heuristic is unambiguous in practice.
- **Hop header stripping.** `cf-connecting-ip`, `cf-ray`, `cf-visitor`, `x-forwarded-for` and friends are deleted before forwarding so Medium's edge sees an intra-Cloudflare request without datacenter fingerprints.
- **Image cache.** Successful miro responses get a `Cache-Control: public, max-age=86400` header so repeat fetches don't keep round-tripping.

For a more complete walkthrough — request streaming, WAF tuning, the full GraphQL operation reference, and notes on how Medium's bot detection evolves — see:

> **[Medium x Cloudflare: Offense and Defense](https://en.zhgchg.li/posts/88f0fb935120/#medium-x-cloudflare-offense-and-defense)**

### Pointing ZMediumToMarkdown at your proxy

One Worker, one URL, one secret. Two env vars total:

| Variable | Default | Purpose |
|---|---|---|
| `MEDIUM_HOST` | `https://medium.com/_/graphql` | GraphQL endpoint and base host for *every* medium.com / miro.medium.com hit (the Worker handles both via path dispatch). Set to `https://<your-worker>.<your-account>.workers.dev/_/graphql`. |
| `MEDIUM_HOST_SECRET` | *(unset)* | Shared secret. When set, the gem adds `X-Medium-Proxy-Secret: <value>` to every request bound for the proxy host. Must match the `SECRET` constant in the Worker script. |

`MEDIUM_HOST` overrides propagate automatically to every `https://medium.com/<path>` the gem hits: GraphQL POSTs, iframe metadata at `/media/<id>`, OG-image fallback for embedded post URLs at `/<user>/<post>`, etc. — all of them go through the proxy.

Example:

```bash
export MEDIUM_HOST="https://your-worker.your-account.workers.dev/_/graphql"
export MEDIUM_HOST_SECRET="<your-secret>"
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"

ZMediumToMarkdown -u zhgchgli --jekyll
```

In GitHub Actions — proxy host, secret, and cookies all flow through `env:`, so secret values never appear in the `command` string or logs:

```yaml
- uses: ZhgChgLi/ZMediumToMarkdown@main
  env:
    MEDIUM_HOST:        ${{ secrets.MEDIUM_HOST }}
    MEDIUM_HOST_SECRET: ${{ secrets.MEDIUM_HOST_SECRET }}
    MEDIUM_COOKIE_SID:  ${{ secrets.MEDIUM_COOKIE_SID }}
    MEDIUM_COOKIE_UID:  ${{ secrets.MEDIUM_COOKIE_UID }}
  with:
    command: '-u zhgchgli'
```

### Cookies + Worker = the recommended setup for CI

These two mitigations are independent and complementary:

- Cookies tell Medium *who* you are (Member access, paywall content).
- The Worker tells Cloudflare *where* the request is coming from (intra-Cloudflare, not a flagged IP).

For anything beyond casual local use — scheduled GitHub Actions backups, Docker cron jobs, sharing the tool with a team — **set up both**. It's the difference between runs that "usually work" and runs that consistently work.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Unauthenticated request, or your IP is on Cloudflare's bot list. | **Local with Chrome installed**: just run again on a TTY — the auto-login flow opens Chrome and refreshes cookies for you (Section 1a). **Local without Chrome**: open <https://medium.com> in any browser, clear the challenge, then rerun. **CI / datacenter**: provide cookies (`-s` / `-d` or env vars) and route via a Cloudflare Worker — see Sections 1b and 2. |
| Worker returns `403 Forbidden` to gem requests | `MEDIUM_HOST_SECRET` is unset, doesn't match the Worker's `SECRET` constant, or the Worker URL is being hit from outside the gem (e.g. a curl test without the header). | Verify both values match. From the gem side, `MEDIUM_HOST_SECRET` must be set in the same env as `MEDIUM_HOST`. From the Worker side, redeploy after editing `SECRET`. For curl testing, pass `-H "X-Medium-Proxy-Secret: <value>"`. |
| `This post is behind Medium's paywall…` even though cookies are set | Cookies don't belong to a Medium Member account, or they've expired (~2 weeks). | Refresh `sid` / `uid` (re-run the Section 1a auto-login on a TTY, or repeat Section 1b manually); verify the account has Membership access to the post. |
| Auto-login opens Chrome but no cookies are captured | Login wasn't completed, or the page was navigated away from `medium.com` before pressing Enter. | Stay on a `medium.com` page after signing in, then return to the terminal and press Enter. If the issue persists, fall back to the manual flow in Section 1b. |
| Auto-login doesn't trigger on a TTY | `--non-interactive` was passed, `MEDIUM_NO_AUTO_BROWSER=1` is set, the session is detected as CI, or Chrome isn't installed. | Drop the flag / env var; install Google Chrome; or extract cookies manually (Section 1b). |
| Cached cookies look stale / I want to force a fresh login | Cache file at `~/.zmediumtomarkdown` is still valid but no longer correct (e.g. you switched accounts). | `rm ~/.zmediumtomarkdown` and run again — the auto-login flow will fire and rewrite the cache. |
| `Error: Too Many Requests, blocked by Medium` | Hit Medium's rate limit. | Slow the schedule down or split the run; the tool already retries up to 10 times. |
| Worker returns 1101 / 1102 errors | Worker script error or exceeded CPU time on a single request. | Check the Worker logs in the Cloudflare dashboard; the article in Section 2 has a known-good script. |

---

## Further reading

- Reference Worker implementation: [`worker_example.js`](worker_example.js)
- Full Worker walkthrough + Medium GraphQL reference: <https://en.zhgchg.li/posts/88f0fb935120/#medium-x-cloudflare-offense-and-defense>
- Cloudflare Workers documentation: <https://developers.cloudflare.com/workers/>
- Project README (top-level usage): [`README.md`](https://github.com/ZhgChgLi/ZMediumToMarkdown/blob/main/README.md)
