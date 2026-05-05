require 'fileutils'
require 'date'
require 'json'
require 'uri'

require 'Parsers/H1Parser'
require 'Parsers/H2Parser'
require 'Parsers/H3Parser'
require 'Parsers/H4Parser'
require 'Parsers/PParser'
require 'Parsers/ULIParser'
require 'Parsers/IframeParser'
require 'Parsers/IMGParser'
require 'Parsers/FallbackParser'
require 'Parsers/BQParser'
require 'Parsers/PREParser'
require 'Parsers/MarkupParser'
require 'Parsers/OLIParser'
require 'Parsers/MIXTAPEEMBEDParser'
require 'Parsers/PQParser'
require 'Parsers/CodeBlockParser'

require 'PathPolicy'
require 'Request'
require 'Post'
require 'User'
require 'Helper'
require 'Models/Paragraph'

class ZMediumFetcher

    attr_accessor :progress, :usersPostURLs, :isForJekyll, :stdoutIO, :stdoutMode

    # Encode-then-decode helper that preserves spaces as %20.
    # Replaces the previous module-level URI.decode monkey patch.
    def self.decodePathPreservingSpaces(url)
        return "" if url.nil?
        URI.decode_www_form_component(url).gsub(" ", "%20")
    end

    class Progress
        attr_accessor :username, :postPath, :currentPostIndex, :totalPostsLength, :currentPostParagraphIndex, :totalPostParagraphsLength, :message, :io

        def printLog()
            info = ""
            if !username.nil?
                if !currentPostIndex.nil? && !totalPostsLength.nil?
                    info += "[#{username}(#{currentPostIndex}/#{totalPostsLength})]"
                else
                    info += "[#{username}]"
                end
            end

            if !postPath.nil?
                info += "-" if info != ""
                if !currentPostParagraphIndex.nil? && !totalPostParagraphsLength.nil?
                    info += "[#{postPath[0..15]}...(#{currentPostParagraphIndex}/#{totalPostParagraphsLength})]"
                else
                    info += "[#{postPath[0..15]}...]"
                end
            end

            if !message.nil?
                info += "-" if info != ""
                info += message
            end

            (io || $stdout).puts info if info != ""
        end
    end

    def initialize
        @progress = Progress.new()
        @usersPostURLs = nil
        @isForJekyll = false
        @stdoutIO = nil
        @stdoutMode = false
    end

    def buildParser(imagePathPolicy, skipImages: false)
        h1Parser = H1Parser.new()
        h2Parser = H2Parser.new()
        h3Parser = H3Parser.new()
        h4Parser = H4Parser.new()
        ppParser = PParser.new()
        uliParser = ULIParser.new()
        oliParser = OLIParser.new()
        mixtapeembedParser = MIXTAPEEMBEDParser.new(isForJekyll)
        pqParser = PQParser.new()
        iframeParser = IframeParser.new(isForJekyll, skipImages: skipImages)
        iframeParser.pathPolicy = imagePathPolicy
        imgParser = IMGParser.new(isForJekyll, skipImages: skipImages)
        imgParser.pathPolicy = imagePathPolicy
        bqParser = BQParser.new()
        preParser = PREParser.new(isForJekyll)
        codeBlockParser = CodeBlockParser.new(isForJekyll)
        fallbackParser = FallbackParser.new()

        chain = [
            h1Parser, h2Parser, h3Parser, h4Parser, ppParser, uliParser, oliParser,
            mixtapeembedParser, pqParser, iframeParser, imgParser, bqParser,
            preParser, codeBlockParser, fallbackParser
        ]
        chain.each_cons(2) { |a, b| a.setNext(b) }

        chain.first
    end

    def downloadPost(postURL, pathPolicy, isPin)
        return downloadPostToStdout(postURL, isPin) if stdoutMode

        postID = Post.getPostIDFromPostURLString(postURL)

        if isForJekyll
            postPath = postID # use only post id is more friendly for url seo
            postPathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath("_posts/zmediumtomarkdown"), pathPolicy.getRelativePath("_posts/zmediumtomarkdown"))
            imagePathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath("assets"), "assets")
        else
            postPath = Post.getPostPathFromPostURLString(postURL)
            postPathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath("zmediumtomarkdown"), pathPolicy.getRelativePath("zmediumtomarkdown"))
            imagePathPolicy = PathPolicy.new(postPathPolicy.getAbsolutePath("assets"), "assets")
        end

        progress.postPath = ZMediumFetcher.decodePathPreservingSpaces(postPath)
        progress.message = "Downloading Post..."
        progress.printLog()

        postInfo = Post.parsePostInfo(postID, imagePathPolicy)
        raise "Error: Post info not found! PostURL: #{postURL}" if postInfo.nil?

        contentInfo = Post.fetchPostParagraphs(postID)
        raise "Error: Paragraph Content not found! PostURL: #{postURL}" if contentInfo.nil?

        isLockedPreviewOnly = contentInfo&.dig("isLockedPreviewOnly")

        sourceParagraphs = contentInfo&.dig("bodyModel", "paragraphs")
        raise "Error: Paragraph not found! PostURL: #{postURL}" if sourceParagraphs.nil?

        progress.message = "Formatting Data..."
        progress.printLog()

        paragraphs = preprocessParagraphs(sourceParagraphs, postID)

        startParser = buildParser(imagePathPolicy)

        progress.totalPostParagraphsLength = paragraphs.length
        progress.currentPostParagraphIndex = 0
        progress.message = "Converting Post..."
        progress.printLog()

        postWithDatePath = "#{postInfo.firstPublishedAt.strftime("%Y-%m-%d")}-#{postPath}"
        absolutePath = ZMediumFetcher.decodePathPreservingSpaces(postPathPolicy.getAbsolutePath("#{postWithDatePath}")) + ".md"

        existingMeta = readExistingFrontMatter(absolutePath)

        if existingMeta[:lastModifiedAt] && existingMeta[:lastModifiedAt] >= postInfo.latestPublishedAt.to_i &&
           !isPin.nil? && isPin == existingMeta[:pin] &&
           !isLockedPreviewOnly.nil? && isLockedPreviewOnly == existingMeta[:lockedPreviewOnly]
            # Already downloaded and nothing has changed!, Skip!
            progress.currentPostParagraphIndex = paragraphs.length
            progress.message = "Skip, Post already downloaded and nothing has changed!"
            progress.printLog()
        else
            Helper.createDirIfNotExist(postPathPolicy.getAbsolutePath(nil))
            File.open(absolutePath, "w+") do |file|
                writePost(file, paragraphs, postInfo, isLockedPreviewOnly, postURL, isPin, startParser)
            end
            FileUtils.touch absolutePath, :mtime => postInfo.latestPublishedAt

            progress.message = if isLockedPreviewOnly
                                   paywallMessage
                               else
                                   "Post Successfully Downloaded!"
                               end
            progress.printLog()
        end

        progress.postPath = nil
    end

    # Stdout fast path: render markdown directly to `stdoutIO` without
    # touching the filesystem and without downloading any images. Image
    # references stay as remote miro.medium.com URLs (or MIRO_MEDIUM_HOST
    # proxy if set).
    def downloadPostToStdout(postURL, isPin)
        postID = Post.getPostIDFromPostURLString(postURL)
        postPath = Post.getPostPathFromPostURLString(postURL)

        progress.postPath = ZMediumFetcher.decodePathPreservingSpaces(postPath)
        progress.message = "Rendering Post..."
        progress.printLog()

        postInfo = Post.parsePostInfo(postID, nil, skipImages: true)
        raise "Error: Post info not found! PostURL: #{postURL}" if postInfo.nil?

        contentInfo = Post.fetchPostParagraphs(postID)
        raise "Error: Paragraph Content not found! PostURL: #{postURL}" if contentInfo.nil?

        isLockedPreviewOnly = contentInfo&.dig("isLockedPreviewOnly")

        sourceParagraphs = contentInfo&.dig("bodyModel", "paragraphs")
        raise "Error: Paragraph not found! PostURL: #{postURL}" if sourceParagraphs.nil?

        progress.message = "Formatting Data..."
        progress.printLog()

        paragraphs = preprocessParagraphs(sourceParagraphs, postID)
        startParser = buildParser(nil, skipImages: true)

        progress.totalPostParagraphsLength = paragraphs.length
        progress.currentPostParagraphIndex = 0
        progress.message = "Converting Post..."
        progress.printLog()

        writePost(stdoutIO, paragraphs, postInfo, isLockedPreviewOnly, postURL, isPin, startParser)

        progress.message = if isLockedPreviewOnly
                               paywallMessage
                           else
                               "Post Successfully Rendered!"
                           end
        progress.printLog()
        progress.postPath = nil
    end

    def downloadPostsByUsername(username, pathPolicy, limit: nil)
        progress.username = username
        progress.message = "Fetching posts..."
        progress.printLog()

        userID = User.convertToUserIDFromUsername(username)
        raise "Medium's Username:#{username} not found!" if userID.nil?

        postURLS = []
        nextID = nil
        loop do
            postPageInfo = User.fetchUserPosts(userID, nextID)
            postURLS.concat(postPageInfo["postURLs"])
            nextID = postPageInfo["nextID"]
            break if nextID.nil?
            break if !limit.nil? && postURLS.length >= limit
        end

        postURLS = postURLS.first(limit) unless limit.nil?

        @usersPostURLs = postURLS.map { |post| post["url"] }

        progress.totalPostsLength = postURLS.length
        progress.currentPostIndex = 0
        progress.message = "Downloading posts..."
        progress.printLog()

        downloadPathPolicy = nil
        unless stdoutMode
            downloadPathPolicy = if isForJekyll
                                     pathPolicy
                                 else
                                     PathPolicy.new(pathPolicy.getAbsolutePath("users/#{username}"), pathPolicy.getRelativePath("users/#{username}"))
                                 end
        end

        postURLS.each_with_index do |postURL, idx|
            begin
                downloadPost(postURL["url"], downloadPathPolicy, postURL["pin"])
                if stdoutMode && idx < postURLS.length - 1
                    stdoutIO.puts "\n\n---\n\n"
                end
            rescue => e
                if stdoutMode
                    warn e
                else
                    puts e
                end
            end

            progress.currentPostIndex = idx + 1
            progress.message = "Downloading posts..."
            progress.printLog()
        end

        progress.message = "All posts has been downloaded!, Total posts: #{postURLS.length}"
        progress.printLog()
    end

    # Emits one NDJSON line per post (without bodies) to `stdoutIO`,
    # used by `--list -u <username>`. Honors `limit` to short-circuit
    # pagination and per-post metadata fetch as soon as we have enough.
    def listPostsByUsername(username, limit = nil)
        progress.username = username
        progress.message = "Fetching posts list..."
        progress.printLog()

        userID = User.convertToUserIDFromUsername(username)
        raise "Medium's Username:#{username} not found!" if userID.nil?

        postURLS = []
        nextID = nil
        loop do
            postPageInfo = User.fetchUserPosts(userID, nextID)
            postURLS.concat(postPageInfo["postURLs"])
            nextID = postPageInfo["nextID"]
            break if nextID.nil?
            break if !limit.nil? && postURLS.length >= limit
        end

        postURLS = postURLS.first(limit) unless limit.nil?

        progress.totalPostsLength = postURLS.length
        progress.currentPostIndex = 0
        progress.message = "Listing posts..."
        progress.printLog()

        postURLS.each_with_index do |entry, idx|
            url = entry["url"]
            pin = entry["pin"]

            begin
                postID = Post.getPostIDFromPostURLString(url)
                info = Post.parsePostInfo(postID, nil, skipImages: true)
                if info.nil?
                    warn "Skipping #{url}: post info not found"
                else
                    line = {
                        "title"             => info.title,
                        "url"               => url,
                        "creator"           => info.creator,
                        "firstPublishedAt"  => info.firstPublishedAt&.iso8601,
                        "latestPublishedAt" => info.latestPublishedAt&.iso8601,
                        "tags"              => info.tags || [],
                        "description"       => info.description,
                        "pin"               => pin == true
                    }
                    stdoutIO.puts JSON.generate(line)
                end
            rescue => e
                warn "Error listing post #{url}: #{e.message}"
            end

            progress.currentPostIndex = idx + 1
            progress.message = "Listing posts..."
            progress.printLog()
        end

        progress.message = "All posts listed!, Total posts: #{postURLS.length}"
        progress.printLog()
    end

    # ------------------------------------------------------------------
    # Internal helpers (kept public-ish for tests / clarity)
    # ------------------------------------------------------------------

    # Renders a post body to `io` (a File or any IO-like object). Shared by
    # the filesystem path and the stdout path.
    def writePost(io, paragraphs, postInfo, isLockedPreviewOnly, postURL, isPin, startParser)
        postMetaInfo = Helper.createPostInfo(postInfo, isPin, isLockedPreviewOnly, isForJekyll)
        io.puts(postMetaInfo) unless postMetaInfo.nil?

        paragraphs.each_with_index do |paragraph, index|
            io.puts(renderParagraph(paragraph, startParser))

            progress.currentPostParagraphIndex = index + 1
            progress.message = "Converting Post..."
            progress.printLog()
        end

        if isLockedPreviewOnly
            viewFullPost = Helper.createViewFullPost(postURL, isForJekyll)
            io.puts(viewFullPost) unless viewFullPost.nil?
        else
            postWatermark = Helper.createWatermark(postURL, isForJekyll)
            io.puts(postWatermark) unless postWatermark.nil?
        end
    end

    # Reads YAML-ish front matter from a previously-generated post and
    # returns the fields we care about for skip-already-downloaded logic.
    def readExistingFrontMatter(absolutePath)
        meta = { lastModifiedAt: nil, pin: false, lockedPreviewOnly: false }
        return meta unless File.file?(absolutePath)

        lines = File.foreach(absolutePath).first(15)
        return meta unless lines.first&.start_with?("---")

        latestPublishedAtLine = lines.find { |line| line.start_with?("last_modified_at:") }
        if latestPublishedAtLine
            value = latestPublishedAtLine[/^(last_modified_at:)\s+(\S*)/, 2]
            meta[:lastModifiedAt] = Time.parse(value).to_i if value
        end

        pinLine = lines.find { |line| line.start_with?("pin:") }
        meta[:pin] = pinLine[/^(pin:)\s+(\S*)/, 2].to_s.downcase == "true" if pinLine

        lockedLine = lines.find { |line| line.start_with?("lockedPreviewOnly:") }
        meta[:lockedPreviewOnly] = lockedLine[/^(lockedPreviewOnly:)\s+(\S*)/, 2].to_s.downcase == "true" if lockedLine

        meta
    end

    # Wording branches on whether the user supplied Medium auth cookies, so
    # they get an actionable next step: provide cookies vs. check that
    # cookies belong to a Medium Member account that has access to the post.
    def paywallMessage
        if !defined?($cookies) || $cookies.nil? || ($cookies['sid'].to_s.empty? && $cookies['uid'].to_s.empty?)
            "This post is behind Medium's paywall. Cookies (sid / uid) are REQUIRED to download the full content — without them you only get the public preview. Setup guide: https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy"
        else
            "This post is behind Medium's paywall and the provided cookies don't grant access. Verify your sid / uid belong to a Medium Member account that can read this post. Cookies stay valid as long as they're being used (each successful request resets a ~2-week sliding window); they only expire after ~2 weeks of inactivity."
        end
    end

    # Runs MarkupParser (when applicable) and the parser chain on a single
    # Paragraph, returning the rendered markdown string.
    def renderParagraph(paragraph, startParser)
        unless CodeBlockParser.isCodeBlock(paragraph) || PREParser.isPRE(paragraph)
            markupParser = MarkupParser.new(paragraph, isForJekyll)
            markupParser.usersPostURLs = usersPostURLs
            paragraph.text = markupParser.parse()
        end
        startParser.parse(paragraph)
    end

    # Walks the raw Medium paragraph dicts and produces a list of Paragraph
    # objects, normalizing OLI numbering, inserting blank separators between
    # list/quote runs, and merging adjacent PRE paragraphs into one CodeBlock.
    def preprocessParagraphs(sourceParagraphs, postID)
        paragraphs = []
        oliIndex = 0
        previousParagraph = nil
        preTypeParagraphs = []

        sourceParagraphs.each do |sourceParagraph|
            next if !sourceParagraph || !postID
            paragraph = Paragraph.new(sourceParagraph, postID)

            if OLIParser.isOLI(paragraph)
                oliIndex += 1
                paragraph.oliIndex = oliIndex
            else
                oliIndex = 0
            end

            if (OLIParser.isOLI(previousParagraph) && !OLIParser.isOLI(paragraph)) ||
               (ULIParser.isULI(previousParagraph) && !ULIParser.isULI(paragraph)) ||
               (BQParser.isBQ(previousParagraph) && !BQParser.isBQ(paragraph))
                paragraphs.append(Paragraph.makeBlankParagraph(postID))
            end

            if PREParser.isPRE(paragraph)
                preTypeParagraphs.append(paragraph)
            elsif PREParser.isPRE(previousParagraph)
                flushPreParagraphsInto(paragraphs, preTypeParagraphs)
                preTypeParagraphs = []
            end

            paragraphs.append(paragraph)
            previousParagraph = paragraph
        end

        # Flush any trailing PRE run (fixes posts that end in code blocks).
        flushPreParagraphsInto(paragraphs, preTypeParagraphs)

        paragraphs
    end

    # Collapses a run of PRE paragraphs already in `paragraphs` into a single
    # CODE_BLOCK paragraph. The last PRE in the run is rewritten in place to
    # hold the joined text; all earlier PREs are dropped.
    def flushPreParagraphsInto(paragraphs, preTypeParagraphs)
        return if preTypeParagraphs.length <= 1

        last = preTypeParagraphs.last
        last.text = preTypeParagraphs.map(&:orgText).join("\n")
        last.type = CodeBlockParser.getTypeString()

        droppedNames = preTypeParagraphs[0...-1].map(&:name)
        paragraphs.reject! { |p| droppedNames.include?(p.name) }
    end
end
