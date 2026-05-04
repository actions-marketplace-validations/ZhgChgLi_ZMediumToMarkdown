require 'uri'
require 'nokogiri'

require 'Request'
require 'Parsers/Parser'
require 'Parsers/TwitterEmbed'
require 'Models/Paragraph'
require 'Helper'
require 'ImageDownloader'
require 'PathPolicy'

class IframeParser < Parser
    attr_accessor :nextParser, :pathPolicy, :isForJekyll

    GIST_HOST_REGEX     = /^https:\/\/gist\.github\.com/.freeze
    EMBEDLY_HOST_REGEX  = /cdn\.embedly\.com/.freeze

    # Twitter rebranded to X — match both, plus the mobile subdomain. Capture
    # group 1 is the tweet ID (used by parseTwitterEmbed).
    TWITTER_URL_REGEX   = /^https:\/\/(?:(?:mobile\.)?twitter|x)\.com\/[^\/]+\/status\/(\d+)/.freeze

    # Match every YouTube URL form Medium might hand us:
    #   www.youtube.com/watch?v=ID    youtu.be/ID    youtube.com/shorts/ID    m.youtube.com/...
    YOUTUBE_HOST_REGEX  = /(?:www\.|m\.)?youtube\.com|youtu\.be/.freeze

    VIMEO_URL_REGEX     = /^https?:\/\/(?:www\.|player\.)?vimeo\.com\/(?:video\/)?(\d+)/.freeze
    SOUNDCLOUD_URL_REGEX = /^https?:\/\/(?:www\.)?soundcloud\.com\/[^\/]+\/[^?\/]+/.freeze
    SPOTIFY_URL_REGEX   = /^https?:\/\/open\.spotify\.com\/(track|album|episode|playlist|show)\/([A-Za-z0-9]+)/.freeze
    WIDGETIC_URL_REGEX  = /^https:\/\/app\.widgetic\.com/.freeze

    def initialize(isForJekyll)
        @isForJekyll = isForJekyll
    end

    def parse(paragraph)
        return forwardToNext(paragraph) unless paragraph.type == 'IFRAME'
        return unless paragraph.iframe

        url = if paragraph.iframe.src.nil? || paragraph.iframe.src == ""
                  "https://medium.com/media/#{paragraph.iframe.id}"
              else
                  paragraph.iframe.src
              end

        return parseYoutube(paragraph, url) if url.match?(YOUTUBE_HOST_REGEX)

        # Resolve embedly wrappers up front so we can dispatch on the inner
        # URL without doing an unnecessary HTTP round-trip for hosts we
        # already know how to handle.
        innerURL = unwrapEmbedly(url)

        return parseTwitterEmbed(paragraph, innerURL)         if innerURL.match?(TWITTER_URL_REGEX)
        return nil                                            if innerURL.match?(WIDGETIC_URL_REGEX)
        return parseVimeo(paragraph, url, innerURL)           if innerURL.match?(VIMEO_URL_REGEX)
        return parseSoundCloud(paragraph, innerURL)           if innerURL.match?(SOUNDCLOUD_URL_REGEX)
        return parseSpotify(paragraph, innerURL)              if innerURL.match?(SPOTIFY_URL_REGEX)

        html = Request.html(Request.URL(url))
        return "" unless html

        srcEl = html.search('script').first
        gistSrc = srcEl ? srcEl.attribute('src').to_s : ""

        if gistSrc.match?(GIST_HOST_REGEX)
            parseGist(gistSrc)
        else
            parseOgImageEmbed(paragraph, innerURL)
        end
    end

    private

    def jekyllOpen
        isForJekyll ? "{:target=\"_blank\"}" : ""
    end

    def forwardToNext(paragraph)
        nextParser&.parse(paragraph)
    end

    def unwrapEmbedly(url)
        return url unless url.match?(EMBEDLY_HOST_REGEX)
        params = embedlyParams(url)
        params["url"] || url
    end

    # Decodes a `cdn.embedly.com` URL and returns its query params hash.
    # Returns {} on any parse failure so callers can branch with `params["url"]`.
    def embedlyParams(url)
        URI.decode_www_form(URI(decodeURL(url)).query || "").to_h
    rescue URI::InvalidURIError, ArgumentError
        {}
    end

    def parseTwitterEmbed(paragraph, ogURL)
        twitterID = ogURL[TWITTER_URL_REGEX, 1]
        return plainLink(paragraph, ogURL) if twitterID.nil?

        TwitterEmbed.render(twitterID, ogURL, jekyllOpen: jekyllOpen) ||
            plainLink(paragraph, ogURL)
    end

    def plainLink(paragraph, ogURL)
        title = paragraph.iframe.title
        title = ogURL if title.nil? || title.empty?
        "[#{title}](#{ogURL})#{jekyllOpen}"
    end

    # YouTube: in Jekyll mode emit a <iframe> player; in plain mode download
    # the embedly-provided thumbnail and emit `[![title](thumb)](videoURL)`.
    def parseYoutube(paragraph, url)
        params = embedlyParams(url)
        targetURL = params["url"] || url
        return plainLink(paragraph, targetURL) if params["url"].nil?

        if isForJekyll
            vid = extractYoutubeVideoID(targetURL)
            return plainLink(paragraph, targetURL) if vid.nil? || vid.empty?
            iframeMarkup("https://www.youtube.com/embed/#{vid}", paragraph.iframe.title || "Youtube",
                         allow: "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture")
        else
            return plainLink(paragraph, targetURL) if params["image"].nil?
            renderThumbnailLink(paragraph, targetURL, params["image"], defaultTitle: "Youtube")
        end
    end

    # YouTube IDs live in three places depending on URL form:
    #   ?v=<id>            (canonical /watch?v=...)
    #   /<id>              (youtu.be short links)
    #   /shorts/<id>       (YouTube Shorts)
    def extractYoutubeVideoID(url)
        uri = URI.parse(url)
        return nil unless uri && uri.host

        if uri.host.include?('youtu.be')
            uri.path.delete_prefix('/').split('/').first
        elsif uri.path.start_with?('/shorts/')
            uri.path.delete_prefix('/shorts/').split('/').first
        else
            URI.decode_www_form(uri.query || '').to_h['v']
        end
    rescue URI::InvalidURIError
        nil
    end

    # Vimeo: same pattern as YouTube. Embedly tends to ship a thumbnail in
    # the `image` query param; if it's missing we fall back to og:image.
    def parseVimeo(paragraph, embedlyURL, innerURL)
        if isForJekyll
            vid = innerURL[VIMEO_URL_REGEX, 1]
            return plainLink(paragraph, innerURL) if vid.nil?
            iframeMarkup("https://player.vimeo.com/video/#{vid}", paragraph.iframe.title || "Vimeo",
                         allow: "autoplay; fullscreen; picture-in-picture", aspectClass: "embed-video")
        else
            params = embedlyParams(embedlyURL)
            imageURL = params["image"]
            imageURL = Helper.fetchOGImage(innerURL) if imageURL.nil? || imageURL.empty?
            return plainLink(paragraph, innerURL) if imageURL.nil? || imageURL.empty?
            renderThumbnailLink(paragraph, innerURL, imageURL, defaultTitle: "Vimeo")
        end
    end

    # SoundCloud: Jekyll mode emits the official iframe player; plain mode
    # has no audio embed option, so we render the OG image card if available
    # and fall back to a plain link.
    def parseSoundCloud(paragraph, innerURL)
        if isForJekyll
            playerURL = "https://w.soundcloud.com/player/?url=#{URI.encode_www_form_component(innerURL)}&color=%23ff5500&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true"
            iframeMarkup(playerURL, paragraph.iframe.title || "SoundCloud",
                         allow: "autoplay", aspectClass: "embed-audio")
        else
            parseOgImageEmbed(paragraph, innerURL)
        end
    end

    # Spotify: Jekyll mode emits the official open.spotify.com/embed iframe;
    # plain mode falls through to OG image / link.
    def parseSpotify(paragraph, innerURL)
        if isForJekyll
            kind = innerURL[SPOTIFY_URL_REGEX, 1]
            id   = innerURL[SPOTIFY_URL_REGEX, 2]
            return plainLink(paragraph, innerURL) if kind.nil? || id.nil?
            iframeMarkup("https://open.spotify.com/embed/#{kind}/#{id}", paragraph.iframe.title || "Spotify",
                         allow: "encrypted-media", aspectClass: "embed-audio")
        else
            parseOgImageEmbed(paragraph, innerURL)
        end
    end

    # Generic Jekyll <iframe> markup used by every video / audio embed.
    def iframeMarkup(src, title, allow:, aspectClass: "embed-video")
        "<iframe class=\"#{aspectClass}\" loading=\"lazy\" src=\"#{src}\" title=\"#{title}\" frameborder=\"0\" allow=\"#{allow}\" allowfullscreen ></iframe>"
    end

    # Downloads `imageURL` into the post asset directory and emits the
    # standard `[![title](relPath)](targetURL)` markdown. Falls back to a
    # plain link if the download fails.
    def renderThumbnailLink(paragraph, targetURL, imageURL, defaultTitle:)
        fileName = "#{paragraph.name}_#{URI(imageURL).path.split("/").last}"
        imagePolicy = PathPolicy.new(pathPolicy.getAbsolutePath(paragraph.postID), pathPolicy.getRelativePath(paragraph.postID))
        absolutePath = imagePolicy.getAbsolutePath(fileName)

        title = paragraph.iframe.title
        title = defaultTitle if title.nil? || title.empty?

        if ImageDownloader.download(absolutePath, imageURL)
            relativePath = imagePolicy.getRelativePath(fileName)
            "\r\n\r\n[![#{title}](#{relativePath} \"#{title}\")](#{targetURL})#{jekyllOpen}\r\n\r\n"
        else
            "\r\n[#{title}](#{targetURL})#{jekyllOpen}\r\n"
        end
    end

    def parseGist(gistSrc)
        gist = Request.body(Request.URL(gistSrc)).scan(/(document\.write\('){1}(.*)(\)){1}/)[1][1]
        gist = gist.gsub('\n', '').gsub('\"', '"').gsub('<\/', '</')
        gistHTML = Nokogiri::HTML(gist)

        gistHTML.search('a').each do |a|
            next unless a.text == 'view raw'

            isMarkdown = false
            lang = gistHTML.search('table').first['data-tagsearch-lang']
            if !lang.nil?
                lang = lang.downcase
                if isForJekyll && lang == "objective-c"
                    lang = "objectivec"
                elsif lang == "protocol buffer"
                    lang = "protobuf"
                end
            else
                viewRawURL = a['href']
                extName = File.extname(viewRawURL).delete_prefix(".")
                if extName == "md"
                    isMarkdown = true
                else
                    lang = extName
                end
            end

            gistRAW = Request.body(Request.URL(a['href']))

            return isMarkdown ? "\n#{gistRAW.chomp}\n\n" : "```#{lang}\n#{gistRAW.chomp}\n```"
        end

        nil
    end

    def parseOgImageEmbed(paragraph, ogURL)
        ogImageURL = Helper.fetchOGImage(ogURL)
        title = paragraph.iframe.title
        title = Helper.escapeMarkdown(ogURL) if title.nil? || title == ""

        if !ogImageURL.nil? && ogImageURL != ""
            "\r\n\r\n[![#{title}](#{ogImageURL} \"#{title}\")](#{ogURL})#{jekyllOpen}\r\n\r\n"
        else
            "[#{title}](#{ogURL})#{jekyllOpen}"
        end
    end

    def decodeURL(url)
        URI.decode_www_form_component(url).gsub(" ", "%20")
    end
end
