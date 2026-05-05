require 'CookieCache'

# Drive a visible Chrome (via ferrum / CDP) to let the user sign into Medium
# in a real browser, then read sid/uid/cf_clearance/_cfuvid back out of the
# session. Used both for first-time setup (no cookies on disk) and as the
# Cloudflare-block recovery flow (cf_clearance refresh).
#
# "Headless" in the user's spec is a misnomer — login is interactive, so we
# launch with headless:false and rely on the user to complete the login
# in the visible window before pressing Enter.
module ChromeAuth
    TARGET_COOKIES = %w[sid uid cf_clearance _cfuvid].freeze
    LOGIN_URL      = 'https://medium.com/m/signin'.freeze
    REFRESH_URL    = 'https://medium.com'.freeze

    @@session = nil

    module_function

    # True iff ferrum loads AND a Chrome binary is detectable. Anything
    # else returns false so the caller can fall back to the legacy
    # default-browser flow without aborting.
    def available?
        require 'ferrum'
        path = Ferrum::Browser::Options::Chrome.options.detect_path
        !path.nil? && !path.empty?
    rescue LoadError, StandardError
        false
    end

    # ---- Single-shot CLI flow ---------------------------------------
    # Open Chrome at openURL, wait for the user to press Enter, then
    # collect the four target cookies. Returns hash { 'sid' => '...', ... }
    # — keys missing from the browser are simply omitted, so callers must
    # check what came back rather than assume completeness.
    #
    # Raises StandardError on browser launch / navigation failure; callers
    # are expected to rescue and degrade gracefully.
    def login!(errput: $stderr, input: $stdin, openURL: LOGIN_URL)
        startSession!(openURL: openURL)
        promptUser(errput, input, openURL)
        finishSession!
    rescue StandardError
        cancelSession!
        raise
    end

    # ---- Split flow for MCP / other long-lived hosts ----------------
    # `startSession!` / `finishSession!` / `cancelSession!` let a caller
    # spawn the browser in one tool call and harvest cookies in another,
    # using the host process (e.g. an MCP server) as the place that
    # holds the still-open browser between calls.
    #
    # Lifecycle:
    #   startSession!  → opens browser, returns immediately. If a session
    #                    is already alive, that one is force-cancelled
    #                    first so a stale browser can't strand cookies.
    #   finishSession! → reads cookies from the live browser, writes
    #                    cache, quits browser, clears session, returns
    #                    the cookies hash.
    #   cancelSession! → quit + clear; idempotent.
    #
    # Not thread-safe: assumes a single MCP request handler at a time.
    def startSession!(openURL: LOGIN_URL)
        cancelSession! if sessionActive?
        browser = buildBrowser
        browser.go_to(openURL)
        @@session = { browser: browser, openURL: openURL, startedAt: Time.now }
        { ok: true, openURL: openURL }
    rescue StandardError
        # If go_to or anything else blew up, make sure we don't leave a
        # half-built browser around with no handle.
        begin
            browser&.quit
        rescue StandardError
            # ignore
        end
        @@session = nil
        raise
    end

    def finishSession!
        raise 'No active ChromeAuth session — call startSession! first.' unless sessionActive?
        browser = @@session[:browser]
        cookies = collectMediumCookies(browser)
        CookieCache.save(CookieCache.load.merge(cookies)) if cookies.any?
        cookies
    ensure
        cancelSession!
    end

    def cancelSession!
        return false unless sessionActive?
        browser = @@session[:browser]
        @@session = nil
        begin
            browser&.quit
        rescue StandardError
            # ignore: best-effort shutdown
        end
        true
    end

    def sessionActive?
        !@@session.nil?
    end

    # Factory split out so tests can stub it. Tweaking ferrum options
    # globally (window size, timeouts) belongs here too.
    def buildBrowser
        require 'ferrum'
        Ferrum::Browser.new(
            headless: false,
            window_size: [1280, 900],
            timeout: 60,
            process_timeout: 30
        )
    end

    # Filter the browser's cookie jar down to medium.com cookies whose
    # name is one of TARGET_COOKIES. We accept both .medium.com and
    # medium.com because Cloudflare sets _cfuvid on the apex while
    # Medium tends to set sid/uid on the dot-prefixed domain.
    def collectMediumCookies(browser)
        result = {}
        browser.cookies.each do |cookie|
            next unless TARGET_COOKIES.include?(cookie.name)
            next unless mediumDomain?(cookie.domain)
            result[cookie.name] = cookie.value
        end
        result
    rescue StandardError
        {}
    end

    def mediumDomain?(domain)
        return false if domain.nil?
        normalized = domain.start_with?('.') ? domain[1..] : domain
        normalized == 'medium.com' || normalized.end_with?('.medium.com')
    end

    def promptUser(errput, input, url)
        errput.puts <<~MSG

          ──────────────────────────────────────────────────────────────────────
          🔐 Sign into Medium in the Chrome window that just opened.

          Steps:
            1. Complete login (and any Cloudflare challenge) at #{url}.
            2. Stay on a medium.com page once you're signed in.
            3. Come back here and press Enter — we'll read sid / uid /
               cf_clearance / _cfuvid out of the browser and cache them at
               #{CookieCache.path}.

          (Press Ctrl-D to abort and fall back to manual setup.)
          ──────────────────────────────────────────────────────────────────────
        MSG
        errput.print 'Press Enter when signed in… '
        line = input.gets
        errput.puts
        line
    end
end
