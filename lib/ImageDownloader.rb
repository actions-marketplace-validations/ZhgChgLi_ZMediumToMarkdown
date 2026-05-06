require 'net/http'
require 'uri'

require 'Helper'
require 'Request'

class ImageDownloader
    USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'.freeze
    MAX_REDIRECTS = 5

    # Downloads `url` to disk at `path`. Routes medium.com / miro.medium.com
    # URLs through MEDIUM_HOST when configured (so requests inherit the
    # Worker's IP reputation + auth) and attaches `X-Medium-Proxy-Secret`
    # and the global cookie jar when the destination is the user's proxy.
    # Other hosts (i.ytimg.com, pbs.twimg.com, etc.) are fetched directly.
    def self.download(path, url)
        dir = path.split('/')
        dir.pop
        Helper.createDirIfNotExist(dir.join('/'))

        return true if File.exist?(path)

        rewritten = Request.mediumProxiedURL(url)
        uri = URI.parse(rewritten) rescue nil
        return false if uri.nil? || uri.host.nil?

        response = fetchWithRedirects(uri, MAX_REDIRECTS)
        return false if response.nil? || response.code.to_i != 200

        body = response.body
        return false if body.nil? || body.empty?

        File.binwrite(path, body)
        true
    rescue StandardError
        false
    end

    def self.fetchWithRedirects(uri, limit)
        return nil if limit <= 0

        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = (uri.scheme == 'https')
        https.open_timeout = 10
        https.read_timeout = 60

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = USER_AGENT

        if Request.proxyURI?(uri)
            secret = ENV['MEDIUM_HOST_SECRET'].to_s
            request['X-Medium-Proxy-Secret'] = secret unless secret.empty?
        end

        cookies = $cookies || {}
        cookieString = cookies.reject { |_, v| v.nil? }
                              .map { |k, v| "#{k}=#{v}" }
                              .join('; ')
        request['Cookie'] = cookieString unless cookieString.empty?

        response = https.request(request)

        case response.code.to_i
        when 301, 302, 303, 307, 308
            location = response['location'].to_s
            return nil if location.empty?
            target = URI.parse(URI.join(uri.to_s, location).to_s)
            target = URI.parse(Request.mediumProxiedURL(target.to_s))
            fetchWithRedirects(target, limit - 1)
        else
            response
        end
    end
end
