require 'fileutils'
require 'date'
require 'json'
require 'open-uri'
require 'zip'
require 'nokogiri'

require 'PathPolicy'
require 'Post'
require 'Request'

class Helper

    # Characters with inline markdown meaning at any position — they can
    # always trigger syntax (emphasis, code spans, link/image start), so
    # escape them everywhere.
    INLINE_MARKDOWN_ESCAPE_CHARS = ['\\', '`', '*', '_', '[', ']'].freeze
    INLINE_MARKDOWN_ESCAPE_REGEX = /[\\`*_\[\]]/.freeze

    # Characters that only have meaning at the start of a paragraph
    # (heading, blockquote, unordered list). Inside a line they're plain
    # text and don't need a backslash.
    LINE_START_ESCAPE_CHARS = ['#', '>', '-', '+'].freeze

    def self.fetchOGImage(url)
        html = Request.html(Request.URL(url))
        return "" unless html
        image = html.search("meta[property='og:image']").first
        image ? (image['content'] || "") : ""
    end

    # Escape characters that always have inline markdown meaning. Used for
    # standalone text snippets (e.g. fallback embed titles) where there is
    # no surrounding paragraph context.
    def self.escapeMarkdown(text)
        text.gsub(INLINE_MARKDOWN_ESCAPE_REGEX) { |c| "\\#{c}" }
    end

    # Returns true if `char` at this position would be re-interpreted as
    # markdown when emitted as-is.
    #
    # `precedingChars` is the array of chars (in original order) that
    # appear before `char` in the same paragraph — needed to detect the
    # ordered-list pattern `<digits>.` / `<digits>)` at line start.
    def self.markdownEscapeNeeded?(char, precedingChars)
        return true if INLINE_MARKDOWN_ESCAPE_CHARS.include?(char)

        if precedingChars.empty?
            # Block-level marker at the very start of the paragraph.
            return LINE_START_ESCAPE_CHARS.include?(char)
        end

        # Ordered-list marker: only when the entire prefix is digits.
        if (char == '.' || char == ')') && precedingChars.all? { |c| c.match?(/\d/) }
            return true
        end

        false
    end

    def self.escapeHTML(text, toHTMLEntity = true)
        if toHTMLEntity
            text = text.gsub('<', '&lt;').gsub('>', '&gt;')
        else
            text = text.gsub('<', '\<').gsub('>', '\>')
        end
        text
    end

    def self.createDirIfNotExist(dirPath)
        return if dirPath.nil? || dirPath.empty?
        FileUtils.mkdir_p(dirPath)
    end

    def self.makeWarningText(message)
        puts "####################################################\n"
        puts "#WARNING:\n"
        puts "##{message}\n"
        puts "#--------------------------------------------------#\n"
        puts "#Please feel free to open an Issue or submit a fix/contribution via Pull Request on:\n"
        puts "#https://github.com/ZhgChgLi/ZMediumToMarkdown\n"
        puts "####################################################\n"
    end

    # Pick the latest non-prerelease release from the GitHub releases JSON.
    # Returns nil if `releases` isn't a list (e.g. a rate-limit error body).
    def self.latestStableRelease(releases)
        return nil unless releases.is_a?(Array)
        releases.sort { |a, b| b["id"] <=> a["id"] }.find { |v| v["prerelease"] == false }
    end

    def self.downloadLatestVersion()
        rootPath = File.expand_path('../', File.dirname(__FILE__))

        if File.file?("#{rootPath}/ZMediumToMarkdown.gemspec")
            apiPath = 'https://api.github.com/repos/ZhgChgLi/ZMediumToMarkdown/releases'
            releases = JSON.parse(Request.URL(apiPath).body)
            version = latestStableRelease(releases)
            return if version.nil?

            zipFilePath = version["zipball_url"]
            puts "Downloading latest version from github..."
            URI.open('latest.zip', 'wb') do |fo|
                fo.print URI.open(zipFilePath).read
            end

            puts "Unzip..."
            Zip::File.open("latest.zip") do |zipfile|
                zipfile.each do |file|
                    fileNames = file.name.split("/")
                    fileNames.shift
                    filePath = fileNames.join("/")
                    if filePath != ''
                        puts "Unzip...#{filePath}"
                        zipfile.extract(file, filePath) { true }
                    end
                end
            end
            File.delete("latest.zip")

            puts "Update to version #{version["tag_name"]} successfully!"
        else
            system("gem update ZMediumToMarkdown")
        end
    end

    def self.createPostInfo(postInfo, isPin, isLockedPreviewOnly, isForJekyll)
        title = postInfo.title&.gsub("[", "")&.gsub("]", "")

        tags = ""
        if !postInfo.tags.nil? && postInfo.tags.length > 0
            tags = "\"#{postInfo.tags.map { |tag| tag&.gsub("\"", "\\\"") }.join("\",\"")}\""
        end

        result = "---\n"
        result += "title: \"#{title&.gsub("\"", "\\\"")}\"\n"
        result += "author: \"#{postInfo.creator&.gsub("\"", "\\\"")}\"\n"
        result += "date: #{postInfo.firstPublishedAt.strftime('%Y-%m-%dT%H:%M:%S.%L%z')}\n"
        result += "last_modified_at: #{postInfo.latestPublishedAt.strftime('%Y-%m-%dT%H:%M:%S.%L%z')}\n"
        result += "categories: [\"#{postInfo.collectionName&.gsub("\"", "\\\"")}\"]\n"
        result += "tags: [#{tags}]\n"
        result += "description: \"#{postInfo.description&.gsub("\"", "\\\"")}\"\n"
        if !postInfo.previewImage.nil?
            result += "image:\r\n"
            result += "  path: /#{postInfo.previewImage}\r\n"
        end
        if isPin == true
            result += "pin: true\r\n"
        end
        if isLockedPreviewOnly == true
            result += "lockedPreviewOnly: true\r\n"
        end

        if isForJekyll
            result += "render_with_liquid: false\n"
        end
        result += "---\n"
        result += "\r\n"

        result
    end

    def self.printNewVersionMessageIfExists()
        remote = Helper.getRemoteVersionFromGithub()
        local  = Helper.getLocalVersion()
        return if remote.nil? || local.nil?

        if remote > local
            puts "##########################################################"
            puts "#####           New Version Available!!!             #####"
            puts "##### Please type `ZMediumToMarkdown -n` to update!! #####"
            puts "##########################################################"
        end
    end

    def self.getLocalVersion()
        rootPath = File.expand_path('../', File.dirname(__FILE__))

        result = nil
        if File.file?("#{rootPath}/ZMediumToMarkdown.gemspec")
            gemspecContent = File.read("#{rootPath}/ZMediumToMarkdown.gemspec")
            result = gemspecContent[/(gem\.version){1}\s+(\=)\s+(\'){1}(\d+(\.){1}\d+(\.){1}\d+){1}(\'){1}/, 4]
        else
            result = Gem.loaded_specs["ZMediumToMarkdown"].version.version
        end

        result.nil? ? nil : Gem::Version.new(result)
    end

    def self.getRemoteVersionFromGithub()
        apiPath = 'https://api.github.com/repos/ZhgChgLi/ZMediumToMarkdown/releases'
        releases = JSON.parse(Request.URL(apiPath).body)
        version = latestStableRelease(releases)
        return nil if version.nil?

        tagName = version["tag_name"].to_s.downcase.gsub('v', '')
        Gem::Version.new(tagName)
    end

    def self.createWatermark(postURL, isForJekyll)
        jekyllOpen = isForJekyll ? "{:target=\"_blank\"}" : ""

        text = "\r\n\r\n\r\n"
        text += "_[Post](#{postURL})#{jekyllOpen} converted from Medium by [ZMediumToMarkdown](https://github.com/ZhgChgLi/ZMediumToMarkdown)#{jekyllOpen}._"
        text += "\r\n"

        text
    end

    def self.createViewFullPost(postURL, isForJekyll)
        jekyllOpen = isForJekyll ? "{:target=\"_blank\"}" : ""

        text = "\r\n\r\n\r\n"
        text += "**This [post](#{postURL})#{jekyllOpen} is behind Medium's paywall, View the full [post](#{postURL})#{jekyllOpen} on Medium, converted by [ZMediumToMarkdown](https://github.com/ZhgChgLi/ZMediumToMarkdown)#{jekyllOpen}.**"
        text += "\r\n"

        text
    end
end
