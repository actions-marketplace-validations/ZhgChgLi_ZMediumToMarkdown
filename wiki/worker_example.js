// Cloudflare Worker proxy for ZMediumToMarkdown.
//
// One Worker handles BOTH medium.com and miro.medium.com via path-pattern
// dispatch. The gem only needs MEDIUM_HOST (it derives the miro origin
// from there automatically):
//
//   MEDIUM_HOST          = https://<your-worker>.<your-account>.workers.dev/_/graphql
//   MEDIUM_HOST_SECRET   = <your-secret>     ← matches SECRET below
//
// Dispatch rules (based on incoming path):
//   • /v2/…, /max/…, /freeze/…, /proxy/…, /da/…, /fit/…, or any path
//     containing `*`   → forward to https://miro.medium.com<path>
//   • everything else  → forward to https://medium.com<path>
//
// Auth: every request must carry X-Medium-Proxy-Secret matching the
// SECRET constant below. The gem only sets this header when calling a
// configured custom proxy host, so the secret never leaks to upstream
// Medium. Anything that doesn't match (incl. requests with no header)
// gets a 403 — keeps the Worker from being abused as an open proxy even
// if the workers.dev URL leaks.

export default {
  async fetch(request) {
    // Replace with your own random string (e.g. `openssl rand -base64 32`).
    // Keep in sync with the gem-side MEDIUM_HOST_SECRET env var.
    const SECRET = "REPLACE_ME_WITH_A_LONG_RANDOM_SECRET";

    if (request.headers.get("x-medium-proxy-secret") !== SECRET) {
      return new Response("Forbidden", { status: 403 });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    const isMiroPath =
      path.startsWith("/v2/") ||
      path.startsWith("/max/") ||
      path.startsWith("/freeze/") ||
      path.startsWith("/proxy/") ||
      path.startsWith("/da/") ||
      path.startsWith("/fit/") ||
      path.includes("*");

    const upstreamHost = isMiroPath
      ? "https://miro.medium.com"
      : "https://medium.com";
    const upstream = upstreamHost + path + url.search;

    // Drop Cloudflare / proxy hop headers + the secret itself so the
    // upstream sees an intra-CF request without datacenter fingerprints
    // or our internal auth.
    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.delete("x-medium-proxy-secret");
    headers.delete("cf-connecting-ip");
    headers.delete("cf-ray");
    headers.delete("cf-visitor");
    headers.delete("cf-ipcountry");
    headers.delete("x-forwarded-for");
    headers.delete("x-forwarded-proto");
    headers.delete("x-real-ip");

    if (!headers.has("user-agent")) {
      headers.set(
        "user-agent",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0"
      );
    }

    const init = {
      method: request.method,
      headers,
      redirect: "manual",
    };
    if (!["GET", "HEAD"].includes(request.method)) {
      init.body = request.body;
    }

    const upstreamRes = await fetch(upstream, init);

    // Long-cache image responses; pass everything else through as-is.
    if (isMiroPath && upstreamRes.ok) {
      const respHeaders = new Headers(upstreamRes.headers);
      respHeaders.set("Cache-Control", "public, max-age=86400");
      return new Response(upstreamRes.body, {
        status: upstreamRes.status,
        headers: respHeaders,
      });
    }
    return new Response(upstreamRes.body, {
      status: upstreamRes.status,
      headers: upstreamRes.headers,
    });
  },
};
