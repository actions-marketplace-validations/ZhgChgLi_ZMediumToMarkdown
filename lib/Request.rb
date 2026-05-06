require 'net/http'
require 'nokogiri'
require 'uri'
require 'ChromeAuth'
require 'CookieCache'

class Request
    # Raised when Medium's Cloudflare layer blocks the request (typically
    # the "Just a moment..." challenge page). Carries enough context for
    # the CLI to print actionable cookie-setup guidance.
    class CloudflareBlockedError < StandardError
        attr_reader :http_code, :url

        def initialize(http_code, url)
            @http_code = http_code
            @url = url
            super(buildMessage)
        end

        private

        def buildMessage
            <<~MSG.strip
              Blocked by Medium's Cloudflare layer (HTTP #{http_code}) at #{url}.

              Cloudflare's bot management layer is challenging this request.
              Empirically: ~10 posts without cookies, ~25 posts without a Worker
              proxy from CI / datacenter IPs, before this kicks in.

              Pick the fix that matches where you're running:

                • Local machine (your laptop / desktop):
                    Re-run on a TTY without --non-interactive to trigger
                    the Chrome auto-login flow (captures sid / uid /
                    cf_clearance / _cfuvid). Or open https://medium.com
                    in a normal browser and clear the challenge by hand.

                • CI / CD (GitHub Actions, cloud runners):
                    A human can't clear the challenge. Set up BOTH:
                      1. Medium login cookies (sid / uid) — pass via env
                         MEDIUM_COOKIE_SID and MEDIUM_COOKIE_UID, or via
                         the -s / -d flags. Optionally add cf_clearance
                         / _cfuvid via MEDIUM_COOKIE_CF_CLEARANCE /
                         MEDIUM_COOKIE_CFUVID for short-term unblocking.
                      2. A Cloudflare Worker proxy so requests originate
                         from inside Cloudflare's network instead of a
                         flagged datacenter IP. Point the tool at it via
                         the MEDIUM_HOST env var. (Recommended.)

              Full step-by-step setup guide:
              https://github.com/ZhgChgLi/ZMediumToMarkdown/blob/main/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy.md
            MSG
        end
    end

    CLOUDFLARE_MITIGATION_VALUES = %w[challenge block managed_challenge].freeze

    # Interactive Cloudflare recovery: when running on a developer's own
    # machine (i.e. there is a real TTY and no CI marker env var), instead
    # of just raising CloudflareBlockedError we can open Medium in the
    # user's default browser, let them clear the challenge by hand, and
    # retry the request once. CI environments still raise immediately.
    module InteractiveCloudflareRecovery
        # Common CI env vars. If any of these is set to a non-empty,
        # non-"false" value, we assume non-interactive.
        CI_ENV_VARS = %w[CI GITHUB_ACTIONS GITLAB_CI CIRCLECI JENKINS_URL BUILDKITE TF_BUILD TRAVIS APPVEYOR].freeze

        # Explicit opt-out for users who want the old raise-and-exit behavior
        # even on a TTY.
        DISABLE_ENV_VAR = 'MEDIUM_NO_AUTO_BROWSER'.freeze

        module_function

        def available?(env: ENV, stdin: $stdin, stdout: $stdout)
            return false if env[DISABLE_ENV_VAR].to_s == '1'
            return false if inCIEnvironment?(env)
            stdin.tty? && stdout.tty?
        rescue StandardError
            # Some test stdio doubles don't implement .tty? — treat as non-interactive.
            false
        end

        def inCIEnvironment?(env = ENV)
            CI_ENV_VARS.any? do |key|
                value = env[key].to_s
                !value.empty? && value.downcase != 'false' && value != '0'
            end
        end

        # Build the platform-appropriate command for opening a URL in the
        # default browser. Returned as an array so callers can spawn / system
        # without going through a shell.
        def openCommand(url, hostOS: RbConfig::CONFIG['host_os'])
            case hostOS
            when /darwin/                 then ['open', url]
            when /mswin|mingw|cygwin/     then ['cmd', '/c', 'start', '', url]
            else                               ['xdg-open', url]
            end
        end

        def openInBrowser(url, errput: $stderr)
            spawn(*openCommand(url), out: File::NULL, err: File::NULL)
        rescue Errno::ENOENT, StandardError => e
            errput.puts "(Couldn't auto-open browser — #{e.class}: #{e.message}. Open #{url} manually.)"
        end

        # Run the interactive recovery flow. Returns true if the user
        # cleared the challenge (and, when Chrome is available, we
        # successfully refreshed cookies); false if they pressed Ctrl-D
        # (EOF) or otherwise gave up.
        #
        # Two paths:
        #   1. ChromeAuth available → drive Chrome via ferrum; on success
        #      sid/uid/cf_clearance/_cfuvid land in $cookies and the cache.
        #   2. Otherwise → legacy fallback: open default browser, ask the
        #      user to clear the challenge by hand, retry without new cookies.
        def run(url, errput: $stderr, input: $stdin, autoOpen: true)
            if ChromeAuth.available?
                return runChromeFlow(url, errput: errput, input: input)
            end

            runDefaultBrowserFlow(url, errput: errput, input: input, autoOpen: autoOpen)
        end

        def runChromeFlow(url, errput:, input:)
            errput.puts <<~MSG

              ──────────────────────────────────────────────────────────────────────
              ⚠  Cloudflare bot challenge detected at #{url}.
                 Opening Chrome so you can clear it (and refresh login if needed).
              ──────────────────────────────────────────────────────────────────────

            MSG
            cookies = ChromeAuth.login!(errput: errput, input: input,
                                         openURL: ChromeAuth::REFRESH_URL)
            cookies.each { |k, v| $cookies[k] = v unless v.to_s.empty? }
            !cookies.empty?
        rescue StandardError => e
            errput.puts "(Chrome auto-recovery failed: #{e.class}: #{e.message}. Falling back to default browser.)"
            runDefaultBrowserFlow(url, errput: errput, input: input, autoOpen: true)
        end

        def runDefaultBrowserFlow(url, errput:, input:, autoOpen:)
            errput.puts <<~MSG

              ──────────────────────────────────────────────────────────────────────
              ⚠  Cloudflare bot challenge detected at #{url}.

              Since this looks like an interactive run, you can clear the
              challenge in your browser:
                1. A browser window will open at https://medium.com.
                2. Complete the "Just a moment…" / CAPTCHA challenge there.
                3. Come back here and press Enter to retry.

              (Install Google Chrome to enable auto-cookie capture next time.)
              (To disable this prompt and just fail fast, set #{DISABLE_ENV_VAR}=1.)
              ──────────────────────────────────────────────────────────────────────

            MSG

            openInBrowser('https://medium.com', errput: errput) if autoOpen

            errput.print 'Press Enter once the challenge is cleared (Ctrl-D to give up)… '
            line = input.gets
            errput.puts
            !line.nil?
        end
    end

    # Cap how many times a single self.URL call chain can fall through
    # the Cloudflare-recovery branch, so a user who keeps saying yes to
    # the prompt while Medium keeps blocking can't loop forever.
    CLOUDFLARE_RECOVERY_LIMIT = 5

    def self.URL(url, method = 'GET', data = nil, retryCount = 0)
        retryCount += 1
        url = mediumProxiedURL(url)

        uri = URI(url)
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true

        # --- TLS / Certificate verification setup ---
        # Some OpenSSL builds/configs enable CRL checking, which can fail with:
        # "certificate verify failed (unable to get certificate CRL)".
        # Net::HTTP/OpenSSL does not automatically fetch CRLs, so we use a default
        # cert store and clear CRL-related flags to avoid hard failures while still
        # verifying the peer certificate.
        https.verify_mode = OpenSSL::SSL::VERIFY_PEER

        store = OpenSSL::X509::Store.new
        store.set_default_paths
        # Ensure no CRL-check flags are enabled by default
        store.flags = 0
        https.cert_store = store

        # Allow overriding CA bundle paths via environment variables if needed.
        if ENV['SSL_CERT_FILE'] && !ENV['SSL_CERT_FILE'].empty?
          https.ca_file = ENV['SSL_CERT_FILE']
        end
        if ENV['SSL_CERT_DIR'] && !ENV['SSL_CERT_DIR'].empty?
          https.ca_path = ENV['SSL_CERT_DIR']
        end

        # (Optional) timeouts to avoid hanging on network issues
        https.open_timeout = 10
        https.read_timeout = 30
        # --- end TLS setup ---

        if method.upcase == "GET"
            request = Net::HTTP::Get.new(uri)
        else
            request = Net::HTTP::Post.new(uri)
            request['Content-Type'] = 'application/json'
            if !data.nil?
                request.body = JSON.dump(data)
            end
        end

        request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0';

        cookiesString = $cookies.reject { |_, value| value.nil? }
        .map { |key, value| "#{key}=#{value}" }
        .join("; ");

        if !cookiesString.nil? && cookiesString != ""
          request['Cookie'] = cookiesString;
        end

        # When the request is going to a configured Worker proxy (and only
        # then), attach the user's MEDIUM_HOST_SECRET as a header so the
        # Worker can authenticate the caller. Skipped for upstream
        # medium.com / miro.medium.com so the secret never leaks to Medium.
        if proxyURI?(uri) && (proxySecret = ENV['MEDIUM_HOST_SECRET'].to_s) && !proxySecret.empty?
            request['X-Medium-Proxy-Secret'] = proxySecret
        end

        response = https.request(request);

        setCookieString = response.get_fields('set-cookie');
        if !setCookieString.nil? && setCookieString != ""
          setCookies = setCookieString.map { |cookie| cookie.split('; ').first }.each_with_object({}) do |cookie, hash|
            key, value = cookie.split('=', 2) # Split by '=' into key and value
            hash[key] = value
          end;

          setCookies.each do |key, value|
            $cookies[key] = value
          end
        end

        if cloudflareBlocked?(response)
            # On every Cloudflare block — even when cookies are already
            # set — re-run the recovery flow on a TTY. ChromeAuth refreshes
            # sid/uid/cf_clearance/_cfuvid into $cookies + the cache, so
            # the next attempt usually succeeds. Bounded by retryCount so
            # a degenerate loop (user keeps clearing, Medium keeps blocking)
            # eventually surfaces the error. CI / non-TTY just raises.
            if retryCount <= CLOUDFLARE_RECOVERY_LIMIT && InteractiveCloudflareRecovery.available?
                if InteractiveCloudflareRecovery.run(url)
                    return self.URL(url, method, data, retryCount)
                end
            end
            raise CloudflareBlockedError.new(response.code.to_i, url)
        end

        # 3XX Redirect
        if response.code.to_i == 429
          if retryCount >= 10
            raise "Error: Too Many Requests, blocked by Medium. URL: #{url}"
          else
            response = self.URL(url, method, data, retryCount);
          end
        elsif response.code.to_i >= 300 && response.code.to_i <= 399 && !response['location'].nil? && response['location'] != ''
            if retryCount >= 10
                raise "Error: Retry limit reached. URL: #{url}"
            else
                location = response['location']
                if !location.match? /^(http)/
                    location = "#{uri.scheme}://#{uri.host}#{location}"
                end

                response = self.URL(location, method, data, retryCount)
            end
        end

        response
    end

    # If the user has configured a Cloudflare Worker proxy via MEDIUM_HOST,
    # rewrite *any* https://medium.com/<path> URL to <worker-origin>/<path>
    # so non-GraphQL hits (iframe metadata at /media/<id>, OG-image fallback
    # to /<user>/<post>, etc.) also benefit from the proxy. GraphQL callers
    # already hand us the proxy URL directly via ENV['MEDIUM_HOST'], so they
    # short-circuit the rewrite.
    def self.mediumProxiedURL(url)
        return url unless url.is_a?(String) && url.start_with?('https://medium.com/')
        origin = mediumProxyOrigin
        return url if origin.nil?
        url.sub(%r{\Ahttps://medium\.com}, origin)
    end

    # Extract the `<scheme>://<host>[:port]` of MEDIUM_HOST, or nil if no
    # proxy is configured (or it still points at medium.com itself).
    def self.mediumProxyOrigin
        host = ENV['MEDIUM_HOST'].to_s
        return nil if host.empty?
        uri = URI.parse(host)
        return nil if uri.host.nil? || uri.host == 'medium.com'
        port = (uri.port && uri.port != uri.default_port) ? ":#{uri.port}" : ''
        "#{uri.scheme}://#{uri.host}#{port}"
    rescue URI::InvalidURIError
        nil
    end

    # Resolve the host the gem should use for miro.medium.com image fetches.
    # Single-Worker setups: the same MEDIUM_HOST proxy handles both medium.com
    # and miro.medium.com via path dispatch, so we always derive miro from
    # MEDIUM_HOST's origin. No proxy → upstream miro.medium.com.
    def self.miroHost
        mediumProxyOrigin || 'https://miro.medium.com'
    end

    # True iff `uri` is hosted by the configured Worker proxy — i.e. its
    # host matches MEDIUM_HOST and MEDIUM_HOST is set to something other
    # than upstream medium.com. Used to gate the MEDIUM_HOST_SECRET auth
    # header so the secret only leaves the process when heading to the
    # user's own proxy.
    def self.proxyURI?(uri)
        return false if uri.nil? || uri.host.nil?
        envValue = ENV['MEDIUM_HOST'].to_s
        return false if envValue.empty?
        parsed = URI.parse(envValue) rescue nil
        return false if parsed.nil? || parsed.host.nil?
        parsed.host != 'medium.com' && parsed.host == uri.host
    end

    # Cloudflare tags blocked responses via either the cf-mitigated header
    # or the standard "Just a moment..." challenge HTML. We check both
    # so we catch challenges even on Cloudflare deployments that don't
    # set the explicit header.
    def self.cloudflareBlocked?(response)
        return false if response.nil?
        code = response.code.to_i
        return false unless code == 403 || code == 503

        mitigated = response['cf-mitigated'].to_s.downcase
        return true if CLOUDFLARE_MITIGATION_VALUES.include?(mitigated)

        body = response.body.to_s
        return false if body.empty?
        body.include?('Just a moment...') ||
            body.include?('cf-error-details') ||
            body.include?('Attention Required')
    end

    def self.html(response)
      body = readBodyAsUTF8(response)
      body.nil? ? nil : Nokogiri::HTML(body)
    end

    def self.body(response)
      readBodyAsUTF8(response)
    end

    # Net::HTTP#read_body returns ASCII-8BIT (binary). Without an explicit
    # UTF-8 tag, downstream parsers misinterpret multi-byte sequences:
    # Nokogiri's encoding sniffer falls back to ISO-8859-1 for inline
    # <script> contents, which then mojibakes the embedded JSON (e.g. CJK
    # comes back as garbage like "ä½¿" instead of "使").
    def self.readBodyAsUTF8(response)
      return nil if response.nil? || response.code.to_i != 200
      body = response.read_body
      return body if body.nil? || body.empty?
      body.force_encoding(Encoding::UTF_8)
      body
    end
end
