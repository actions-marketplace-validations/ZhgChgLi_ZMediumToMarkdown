# Setting Up Medium Cookies and a Cloudflare Worker Proxy

Medium's GraphQL endpoint sits behind Cloudflare's bot management layer. Out of the box, two things tend to break unauthenticated runs:

1. **Cloudflare blocks the request** with an HTTP 403 "Just a moment…" challenge — particularly common from cloud runners (GitHub Actions, datacenter IPs, headless browsers).
2. **Paywalled posts** come back with `isLockedPreviewOnly: true` and only the public preview text is returned by Medium.

To run reliably, both of the following are **strongly recommended**. They solve different problems and stack — set up both for the smoothest experience.

- **Medium login cookies (`sid`, `uid`)** — unlock paywalled posts and authenticate you as a Medium Member. Required for full content.
- **Cloudflare Worker proxy** — make requests originate from inside Cloudflare's own network so datacenter IPs don't get bot-checked. Required for reliable runs from CI / Docker / cloud runners.

---

## 1. How to Get Your Medium Cookies (`sid`, `uid`)

### Why you need them

Without these cookies, Medium treats every request as anonymous. That means:

- Cloudflare is more aggressive about challenging the request.
- Any post behind the Member paywall is returned in preview-only form, no matter how many times you retry.

The `sid` cookie carries your session token; `uid` identifies your account. Both are issued by Medium when you log in via a browser.

### Steps

1. Open <https://medium.com> in a browser and **make sure you are logged in** to your Medium account. If you have a Member subscription, log in with the Member account so paywalled posts you can normally read are also unlocked here.
2. Open DevTools:
    - **Chrome / Edge**: `View → Developer → Developer Tools` (or `F12`), then go to the **Application** tab.
    - **Firefox**: `Tools → Browser Tools → Web Developer Tools`, then go to the **Storage** tab.
    - **Safari**: enable the Develop menu (`Settings → Advanced → Show Develop menu`), then `Develop → Show Web Inspector`, and go to the **Storage** tab.
3. In the left-hand panel, expand **Cookies** and select `https://medium.com`.
4. Find the rows named `sid` and `uid`. Copy their **Value** column.

> **Cookie expiry & rotation**: Medium issues `sid` / `uid` with roughly a two-week sliding window. As long as the cookies keep being **used** (each successful request resets the clock), they stay valid indefinitely — so a daily or weekly scheduled job typically never needs to refresh them. They only expire when nothing has touched them for two weeks, after which Medium rotates the values and you'll need to copy fresh ones from a logged-in browser. If your scheduled runs suddenly start returning paywall previews or 403s, that's the first thing to check.

> **⚠ Security — treat `sid` / `uid` like passwords.** These are not "preferences" or "settings"; they are **session tokens that fully authenticate as your Medium account**. Anyone who obtains them can read your paywalled content, post / clap / follow as you, and access your account-level information until you sign out. Treat them with the same care as an API key or a database password:
>
> - **Never commit them to a repository**, public or private. Use GitHub Actions secrets, CI environment variables, or a secrets manager.
> - **Never paste them into screenshots, gists, support tickets, or chat logs.** Even a redacted screenshot can leak metadata.
> - **Never share the value with anyone.** If you ever do, sign out of every Medium session immediately (Medium account → Settings → Security → "Sign out of all sessions") to invalidate them, then grab a fresh pair.
> - **Avoid passing them as CLI flags on shared machines** — flags show up in shell history and `ps` output. Prefer the `MEDIUM_COOKIE_SID` / `MEDIUM_COOKIE_UID` environment variables.

### Passing cookies to the CLI

You have two equivalent options. The CLI flag wins if both are set.

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

The most reliable workaround is to send your request through a tiny **Cloudflare Worker** that you deploy on your own free Cloudflare account. The Worker forwards your request to `medium.com` from inside Cloudflare's network — so to Medium's edge, the request looks like it came from another Cloudflare service, not from a flagged datacenter IP.

### Architecture

```
ZMediumToMarkdown                           Your CF Worker                   medium.com
─────────────────                           ──────────────                   ──────────
  GraphQL / HTML  ─── HTTPS POST ───►   <your-worker>.workers.dev   ─────►   medium.com
                                       (rewrites Host header,                Cloudflare
                                        forwards cookies, etc.)              edge sees
                                                                             intra-CF traffic
                                       ◄────── response (proxied) ─────────  → no challenge
```

The Worker is small (a few dozen lines of JavaScript) and stays well within Cloudflare's free tier for personal use.

### Setup walkthrough

### Steps

1. Create a free Cloudflare account if you don't have one.
2. Go to **Workers & Pages → Create → Create Worker**, give it a name (e.g. `medium-proxy`), and click **Deploy** to create the placeholder.
3. Click **Edit code** and paste in the starter script below.
4. Click **Deploy**. You'll get a URL like `https://<your-worker-name>.<your-account>.workers.dev`.
5. Test it:

   ```bash
   curl -X POST https://<your-worker-name>.<your-account>.workers.dev/_/graphql \
     -H "Content-Type: application/json" \
     -d '[{"operationName":"PostViewerEdgeContentQuery","variables":{"postId":"abcdef123456"},"query":"..."}]'
   ```

   You should get a Medium GraphQL response (not a Cloudflare challenge page).

### Starter Worker script

This is the minimum viable proxy — it handles the GraphQL endpoint that `ZMediumToMarkdown` needs and forwards your cookies through. It's deliberately small so you can read every line; extend it as needed.

```javascript
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (path == "/_/graphql") {
      let body;
      try {
        body = await request.json();
      } catch {
        return new Response("Invalid JSON body", { status: 400 });
      }
      let apiURL = "https://medium.com/_/graphql";
      const apiResponse = await fetch(apiURL, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0",
          "Cookie": request.headers.get("cookie")
        },
        body: JSON.stringify(body),
      });
      const json = await apiResponse.json();
      return new Response(JSON.stringify(json), {
        status: apiResponse.status,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
        },
      });
    }
    return new Response("Not Found", { status: 404 });
  },
};
```

Notes on this script:

- The proxy is exposed at the same path Medium uses, **`/_/graphql`**, so `MEDIUM_HOST` for your Worker is just `https://<your-worker-url>/_/graphql` — identical shape to the upstream URL it replaces.
- The `Cookie` header from the incoming request is forwarded as-is, so your `sid` / `uid` reach Medium unchanged. Treat your Worker URL with the same care as your cookies — anyone who can call it can use any cookie value they pass in.
- Only `POST` JSON bodies are handled; `GET` / other methods return 404. That's enough for `ZMediumToMarkdown`, which only POSTs GraphQL.
- The script does **not** proxy `miro.medium.com` (image CDN) or post-page HTML. For most use cases the GraphQL endpoint is the only thing Cloudflare actively challenges, so this is enough. If you also need image proxying, the article below shows a second Worker for that host.

For a more complete walkthrough — request streaming, WAF tuning, image proxy, the full GraphQL operation reference, and notes on how Medium's bot detection evolves — see:

> **[Medium x Cloudflare: Offense and Defense](https://en.zhgchg.li/posts/88f0fb935120/#medium-x-cloudflare-offense-and-defense)**

### Pointing ZMediumToMarkdown at your proxy

The tool reads three environment variables that override the upstream hosts. Set the ones you've proxied:

| Variable | Default | Purpose |
|---|---|---|
| `MEDIUM_HOST` | `https://medium.com/_/graphql` | GraphQL endpoint — point this at your Worker URL with the same `/_/graphql` path (e.g. `https://your-worker.your-account.workers.dev/_/graphql`). |
| `MIRO_MEDIUM_HOST` | `https://miro.medium.com` | Image CDN — point this at your image-proxy Worker if you set one up. |
| `TWITTER_SYNDICATION_HOST` | `https://cdn.syndication.twitter.com` | Tweet embed source. Usually unaffected by the Medium block, but available if needed. |

Example:

```bash
export MEDIUM_HOST="https://your-worker.your-account.workers.dev/_/graphql"
# Optional — only set if you also deployed an image-proxy Worker:
# export MIRO_MEDIUM_HOST="https://your-image-worker.your-account.workers.dev"
export MEDIUM_COOKIE_SID="<your sid>"
export MEDIUM_COOKIE_UID="<your uid>"

ZMediumToMarkdown -u zhgchgli --jekyll
```

In GitHub Actions — proxy hosts and cookies all flow through `env:`, so secret values never appear in the `command` string or logs:

```yaml
- uses: ZhgChgLi/ZMediumToMarkdown@main
  env:
    MEDIUM_HOST: https://your-worker.your-account.workers.dev/_/graphql
    # MIRO_MEDIUM_HOST: https://your-image-worker.your-account.workers.dev   # optional, only if you proxied images too
    MEDIUM_COOKIE_SID: ${{ secrets.MEDIUM_COOKIE_SID }}
    MEDIUM_COOKIE_UID: ${{ secrets.MEDIUM_COOKIE_UID }}
  with:
    command: '-u zhgchgli'
```

### Cookies + Worker = the recommended setup

These two mitigations are independent and complementary:

- Cookies tell Medium *who* you are (Member access, paywall content).
- The Worker tells Cloudflare *where* the request is coming from (intra-Cloudflare, not a flagged IP).

For anything beyond casual local use — scheduled GitHub Actions backups, Docker cron jobs, sharing the tool with a team — **set up both**. It's the difference between runs that "usually work" and runs that consistently work.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Blocked by Medium's Cloudflare layer (HTTP 403)` | Unauthenticated request, or your IP is on Cloudflare's bot list. | Provide cookies (`-s` / `-d` or env vars). If the IP itself is the problem, route via a Cloudflare Worker — see Section 2. |
| `This post is behind Medium's paywall…` even though cookies are set | Cookies don't belong to a Medium Member account, or they've expired (~2 weeks). | Refresh `sid` / `uid` from a logged-in browser; verify the account has access to the post. |
| `Error: Too Many Requests, blocked by Medium` | Hit Medium's rate limit. | Slow the schedule down or split the run; the tool already retries up to 10 times. |
| Worker returns 1101 / 1102 errors | Worker script error or exceeded CPU time on a single request. | Check the Worker logs in the Cloudflare dashboard; the article in Section 2 has a known-good script. |

---

## Further reading

- Full Worker walkthrough + Medium GraphQL reference: <https://en.zhgchg.li/posts/88f0fb935120/#medium-x-cloudflare-offense-and-defense>
- Cloudflare Workers documentation: <https://developers.cloudflare.com/workers/>
- Project README (top-level usage): [`README.md`](https://github.com/ZhgChgLi/ZMediumToMarkdown/blob/main/README.md)
