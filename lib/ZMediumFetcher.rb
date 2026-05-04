require 'fileutils'
require 'date'
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

    attr_accessor :progress, :usersPostURLs, :isForJekyll

    # Encode-then-decode helper that preserves spaces as %20.
    # Replaces the previous module-level URI.decode monkey patch.
    def self.decodePathPreservingSpaces(url)
        return "" if url.nil?
        URI.decode_www_form_component(url).gsub(" ", "%20")
    end

    class Progress
        attr_accessor :username, :postPath, :currentPostIndex, :totalPostsLength, :currentPostParagraphIndex, :totalPostParagraphsLength, :message

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

            puts info if info != ""
        end
    end

    def initialize
        @progress = Progress.new()
        @usersPostURLs = nil
        @isForJekyll = false
    end

    def buildParser(imagePathPolicy)
        h1Parser = H1Parser.new()
        h2Parser = H2Parser.new()
        h3Parser = H3Parser.new()
        h4Parser = H4Parser.new()
        ppParser = PParser.new()
        uliParser = ULIParser.new()
        oliParser = OLIParser.new()
        mixtapeembedParser = MIXTAPEEMBEDParser.new(isForJekyll)
        pqParser = PQParser.new()
        iframeParser = IframeParser.new(isForJekyll)
        iframeParser.pathPolicy = imagePathPolicy
        imgParser = IMGParser.new(isForJekyll)
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

        postHtml = Request.html(Request.URL(postURL))

        postContent = Post.parsePostContentFromHTML(postHtml)
        raise "Error: Content is empty! PostURL: #{postURL}" if postContent.nil?

        postInfo = Post.parsePostInfoFromPostContent(postContent, postID, imagePathPolicy)
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
                postMetaInfo = Helper.createPostInfo(postInfo, isPin, isLockedPreviewOnly, isForJekyll)
                file.puts(postMetaInfo) unless postMetaInfo.nil?

                paragraphs.each_with_index do |paragraph, index|
                    file.puts(renderParagraph(paragraph, startParser))

                    progress.currentPostParagraphIndex = index + 1
                    progress.message = "Converting Post..."
                    progress.printLog()
                end

                if isLockedPreviewOnly
                    viewFullPost = Helper.createViewFullPost(postURL, isForJekyll)
                    file.puts(viewFullPost) unless viewFullPost.nil?
                else
                    postWatermark = Helper.createWatermark(postURL, isForJekyll)
                    file.puts(postWatermark) unless postWatermark.nil?
                end
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

    def downloadPostsByUsername(username, pathPolicy)
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
        end

        @usersPostURLs = postURLS.map { |post| post["url"] }

        progress.totalPostsLength = postURLS.length
        progress.currentPostIndex = 0
        progress.message = "Downloading posts..."
        progress.printLog()

        downloadPathPolicy = if isForJekyll
                                 pathPolicy
                             else
                                 PathPolicy.new(pathPolicy.getAbsolutePath("users/#{username}"), pathPolicy.getRelativePath("users/#{username}"))
                             end

        postURLS.each_with_index do |postURL, idx|
            begin
                downloadPost(postURL["url"], downloadPathPolicy, postURL["pin"])
            rescue => e
                puts e
            end

            progress.currentPostIndex = idx + 1
            progress.message = "Downloading posts..."
            progress.printLog()
        end

        progress.message = "All posts has been downloaded!, Total posts: #{postURLS.length}"
        progress.printLog()
    end

    # ------------------------------------------------------------------
    # Internal helpers (kept public-ish for tests / clarity)
    # ------------------------------------------------------------------

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
            "This post is behind Medium's paywall. Provide your Medium Member cookies (-s SID -d UID) to download the full content. See README -> Cookie setup."
        else
            "This post is behind Medium's paywall and the provided cookies don't grant access. Verify your sid/uid belong to a Medium Member account that can read this post (cookies expire roughly every 2 weeks)."
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
