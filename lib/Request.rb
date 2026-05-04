require 'net/http'
require 'nokogiri'

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

              This usually means the request was made from an environment Cloudflare
              treats as a bot (cloud runners, datacenter IPs, headless browsers) and
              no logged-in Medium cookie was provided.

              Fix:
                1. Open https://medium.com in a logged-in browser.
                2. Open DevTools -> Application/Storage -> Cookies -> medium.com.
                3. Copy the values of the `sid` and `uid` cookies.
                4. Re-run with:    -s YOUR_SID -d YOUR_UID
                   or via env:     MEDIUM_COOKIE_SID=... MEDIUM_COOKIE_UID=...

              Background and a Cloudflare Worker proxy workaround:
              https://zhgchg.li/posts/zrealm-dev/medium-api-%E7%88%AC%E5%8F%96%E8%B3%87%E6%96%99%E8%88%87%E7%AA%81%E7%A0%B4-cloudflare-%E9%98%B2%E8%AD%B7-%E5%AE%8C%E6%95%B4-graphql-%E6%93%8D%E4%BD%9C%E6%95%99%E5%AD%B8-88f0fb935120/
            MSG
        end
    end

    CLOUDFLARE_MITIGATION_VALUES = %w[challenge block managed_challenge].freeze

    def self.URL(url, method = 'GET', data = nil, retryCount = 0)
        retryCount += 1

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

        raise CloudflareBlockedError.new(response.code.to_i, url) if cloudflareBlocked?(response)

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
