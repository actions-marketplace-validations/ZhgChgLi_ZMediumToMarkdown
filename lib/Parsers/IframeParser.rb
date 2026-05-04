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

    YOUTUBE_HOST = "www.youtube.com".freeze
    GIST_HOST_REGEX = /^(https\:\/\/gist\.github\.com)/.freeze
    EMBEDLY_HOST_REGEX = /(cdn\.embedly\.com)/.freeze
    TWITTER_URL_REGEX = /^(https\:\/\/twitter\.com\/){1}.+(\/){1}(\d+)/.freeze
    WIDGETIC_URL_REGEX = /^(https\:\/\/app\.widgetic\.com)/.freeze

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

        return parseYoutube(paragraph, url) if url.match?(/(www\.youtube\.com)/)

        # Resolve embedly wrappers up front so we can dispatch on the inner
        # URL without doing an unnecessary HTTP round-trip for hosts we
        # already know how to handle (twitter, widgetic).
        innerURL = unwrapEmbedly(url)
        return parseTwitterEmbed(paragraph, innerURL) if innerURL.match?(TWITTER_URL_REGEX)
        return nil if innerURL.match?(WIDGETIC_URL_REGEX)

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
        params = URI.decode_www_form(URI(decodeURL(url)).query || "").to_h
        params["url"] || url
    rescue URI::InvalidURIError, ArgumentError
        url
    end

    def parseTwitterEmbed(paragraph, ogURL)
        twitterID = ogURL[TWITTER_URL_REGEX, 3]
        return plainLink(paragraph, ogURL) if twitterID.nil?

        TwitterEmbed.render(twitterID, ogURL, jekyllOpen: jekyllOpen) ||
            plainLink(paragraph, ogURL)
    end

    def plainLink(paragraph, ogURL)
        title = paragraph.iframe.title
        title = ogURL if title.nil? || title.empty?
        "[#{title}](#{ogURL})#{jekyllOpen}"
    end

    def parseYoutube(paragraph, url)
        youtubeURL = URI(decodeURL(url)).query
        params = URI.decode_www_form(youtubeURL || "").to_h
        return "[#{paragraph.iframe.title}](#{url})#{jekyllOpen}" if params["url"].nil?

        if isForJekyll
            vidParams = URI.decode_www_form(URI.parse(params["url"]).query || "").to_h
            vid = vidParams["v"]
            "<iframe class=\"embed-video\" loading=\"lazy\" src=\"https://www.youtube.com/embed/#{vid}\" title=\"#{paragraph.iframe.title}\" frameborder=\"0\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\" allowfullscreen ></iframe>"
        else
            return "[#{paragraph.iframe.title}](#{url})#{jekyllOpen}" if params["image"].nil?

            fileName = "#{paragraph.name}_#{URI(params["image"]).path.split("/").last}"
            imagePathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath(paragraph.postID), pathPolicy.getRelativePath(paragraph.postID))
            absolutePath = imagePathPolicy.getAbsolutePath(fileName)
            title = paragraph.iframe.title
            title = "Youtube" if title.nil? || title == ""

            if ImageDownloader.download(absolutePath, params["image"])
                relativePath = imagePathPolicy.getRelativePath(fileName)
                "\r\n\r\n[![#{title}](#{relativePath} \"#{title}\")](#{params["url"]})#{jekyllOpen}\r\n\r\n"
            else
                "\r\n[#{title}](#{params["url"]})#{jekyllOpen}\r\n"
            end
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
