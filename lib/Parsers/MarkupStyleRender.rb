require 'Models/Paragraph'
require 'Helper'
require 'rangeable'

# Renders a Paragraph's text + Markup list into final markdown.
#
# Pipeline:
#   1. Build a position-indexed `chars` map of the paragraph text. Emoji
#      and other 4-byte chars occupy two slots, mirroring Medium's own
#      paragraph index space — this is what `markup.start` / `markup.end`
#      reference.
#   2. Convert each Markup into a TagChar (start/end positions + start/end
#      strings to emit, plus a `sort` priority for nesting).
#   3. Walk every position, emitting tag-open / char / tag-close in order,
#      with a stack to track nesting and to handle line breaks (close
#      every open tag at the `\n`, then reopen on the next line) and
#      mismatched-end ordering.
#   4. Optimize the resulting char stream:
#        - Strip nested style tags inside ` ` code spans (markdown forbids).
#        - Flatten ESCAPE tags (start `\`, empty end) into literal `\` text.
#        - Tighten spacing around tags (no whitespace just inside a tag,
#          and a space after a closing tag if text follows).
class MarkupStyleRender
    attr_accessor :paragraph, :chars, :encodeType, :isForJekyll, :usersPostURLs

    # URL pattern that anchor markups must match before we emit a link.
    # Anything weirder (mailto:, javascript:, relative paths) is dropped
    # rather than rendered with broken syntax.
    URL_REGEX = /\A(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,6}(:[0-9]{1,5})?(\/.*)?\z/ix.freeze

    class TextChar
        attr_accessor :chars, :type
        def initialize(chars, type)
            @chars = chars
            @type = type
        end
    end

    class TagChar < TextChar
        attr_accessor :sort, :startIndex, :endIndex, :startChars, :endChars
        # NOTE: `endIndex` is decremented by 1 here so it points at the
        # *last covered* index rather than the half-open end. The walker
        # checks `tag.endIndex == index` after emitting char at `index`.
        def initialize(sort, startIndex, endIndex, startChars, endChars)
            @sort = sort
            @startIndex = startIndex
            @endIndex = endIndex - 1
            @startChars = TextChar.new(startChars.chars, 'TagStart')
            @endChars = TextChar.new(endChars.chars, 'TagEnd')
        end
    end

    def initialize(paragraph, isForJekyll)
        @paragraph = paragraph
        @isForJekyll = isForJekyll
        @chars = buildCharIndex(paragraph.text)
    end

    def parse
        if paragraph.markups.nil? || paragraph.markups.empty?
            # No markup tags ⇒ walkCharsWithTags is skipped. For Jekyll
            # output we still need to HTML-escape `<` / `>` so kramdown
            # doesn't treat raw chars in the source text as bare HTML tags.
            # Non-Jekyll output keeps the chars as-is.
            response = if isForJekyll
                chars.values.map do |c|
                    next c if c.chars.empty?
                    escaped = Helper.escapeHTML(c.chars.join, true)
                    TextChar.new(escaped.chars, "Text")
                end
            else
                chars.values
            end
        else
            tags = buildTags(paragraph.markups).sort_by(&:startIndex)
            response = walkCharsWithTags(tags)
        end

        optimize(response)
        response.map { |c| c.chars }.join
    end

    # Public for backwards compat / unit tests; the parse pipeline drives it.
    def optimize(response)
        stripStylesInsideCodeSpans(response)
        flattenEscapeTagsToText(response)
        tightenSpacingAroundTags(response)
        response
    end

    private

    # Position index mirrors Medium's: a 4-byte char (most emoji) takes
    # two slots; the second slot is an empty TextChar placeholder so that
    # tag start/end indices align with what Medium serialized.
    def buildCharIndex(text)
        result = {}
        index = 0
        text.each_char do |char|
            result[index] = TextChar.new([char], "Text")
            index += 1
            if char.bytes.length >= 4
                result[index] = TextChar.new([], "Text")
                index += 1
            end
        end
        result
    end

    def buildTags(markups)
        markups.map { |m| buildTag(m) }.compact
    end

    def buildTag(markup)
        tag = case markup.type
        when "EM"     then TagChar.new(2, markup.start, markup.end, "_",  "_")
        when "CODE"   then TagChar.new(0, markup.start, markup.end, "`",  "`")
        when "STRONG" then TagChar.new(2, markup.start, markup.end, "**", "**")
        when "ESCAPE" then TagChar.new(999, markup.start, markup.end, "\\", "")
        when "A"      then buildAnchorTag(markup)
        else
            Helper.makeWarningText("Undefined Markup Type: #{markup.type}.")
            return nil
        end
        # Stash the originating Markup on the tag so walkCharsWithTags can
        # use it as the Rangeable element key (see #walkCharsWithTags).
        tag&.instance_variable_set(:@_markup, markup)
        tag
    end

    def buildAnchorTag(markup)
        url = (markup.anchorType == "USER") ? "https://medium.com/u/#{markup.userId}" : markup.href
        return nil unless url =~ URL_REGEX

        TagChar.new(1, markup.start, markup.end, "[", "]#{anchorDestination(url)}")
    end

    # Pick between absolute-URL form and a relative path when the link
    # points to another post by the same Medium user (so cross-post
    # navigation in a downloaded archive stays self-contained).
    def anchorDestination(url)
        lastPath = url.split("/").last
        lastQuery = lastPath&.split("-")&.last

        ownPost = usersPostURLs && usersPostURLs.any? do |u|
            u.split("/").last.split("-").last == lastQuery
        end

        if ownPost
            isForJekyll ? "(../#{lastQuery}/)" : "(#{lastPath})"
        else
            isForJekyll ? "(#{url}){:target=\"_blank\"}" : "(#{url})"
        end
    end

    # Walks every char index and dispatches into the open/close hooks. We
    # build two index-keyed Hashes (`opens_at`, `closes_at`) up front so the
    # hot path is O(1) per char instead of the previous O(m) `tags.select`
    # scan; combined with the linear walk over chars that turns total cost
    # from O(L · m) into O(L + m). Same-position tags inside each bucket
    # keep their pre-sorted order from the caller.
    #
    # ESCAPE tags bypass Rangeable entirely. ESCAPE ranges are single-char
    # synthetic markups injected by Paragraph#initialize and they MUST stay
    # disjoint — feeding them through Rangeable would coalesce two ESCAPEs
    # at adjacent positions into a single span, double-emitting the
    # backslash. Non-ESCAPE markups go through Rangeable so identical-type
    # overlapping spans (e.g. two STRONGs that share a few chars) get
    # merged into a single tag pair.
    def walkCharsWithTags(tags)
        rangeable_tags, escape_tags = tags.partition { |t| !escape_tag?(t) }
        merged_tags = mergeTagsViaRangeable(rangeable_tags)
        final_tags = (merged_tags + escape_tags).sort_by(&:startIndex)

        opens_at = Hash.new { |h, k| h[k] = [] }
        closes_at = Hash.new { |h, k| h[k] = [] }
        final_tags.each do |t|
            opens_at[t.startIndex] << t
            closes_at[t.endIndex] << t
        end

        response = []
        stack = []
        chars.each do |index, char|
            if newline?(char)
                emitNewline(char, stack, response)
            end

            openStartingTags(opens_at[index], stack, response) if opens_at.key?(index)
            emitChar(char, stack, response) unless newline?(char)
            closeEndingTags(closes_at[index], stack, response) if closes_at.key?(index)
        end

        # Flush any tags still open at end-of-paragraph.
        stack.reverse_each { |tag| response.push(tag.endChars) }
        response
    end

    # Build a Rangeable from the non-ESCAPE TagChars, then read the merged
    # ranges back out as fresh TagChar instances (one per coalesced span,
    # rather than one per original markup). Each TagChar carries enough
    # info (sort priority, start/end strings) to drive emission, so we
    # reuse a representative original TagChar per Markup as the prototype.
    def mergeTagsViaRangeable(rangeable_tags)
        return [] if rangeable_tags.empty?

        rangeable = Rangeable.new
        proto_by_markup = {}

        rangeable_tags.each do |tag|
            markup = tag.instance_variable_get(:@_markup)
            proto_by_markup[markup] ||= tag
            # TagChar stored endIndex as `end - 1` (last covered slot); restore
            # the half-open `end` for Rangeable's closed-interval insert.
            rangeable.insert(markup, start: tag.startIndex, end: tag.endIndex)
        end

        merged = []
        rangeable.each do |markup, ranges|
            proto = proto_by_markup[markup]
            startCharsStr = proto.startChars.chars.join
            endCharsStr = proto.endChars.chars.join
            ranges.each do |lo, hi|
                # TagChar.new takes the half-open `end`; it stores `end - 1`.
                merged << TagChar.new(proto.sort, lo, hi + 1, startCharsStr, endCharsStr)
            end
        end
        merged
    end

    # ESCAPE markups are emitted as TagChar with startChars == "\\" and
    # empty endChars; identifying them by start-string is simpler than
    # threading a type tag through the TagChar struct.
    def escape_tag?(tag)
        tag.startChars.chars.join == "\\"
    end

    def newline?(char)
        char.chars.join == "\n"
    end

    # Markdown can't carry inline styles across a literal newline — close
    # all open tags before the \n and reopen them after, so each line is
    # individually well-formed.
    def emitNewline(char, stack, response)
        stack.reverse_each { |tag| response.push(tag.endChars) }
        response.append(TextChar.new(char.chars, 'Text'))
        stack.each { |tag| response.push(tag.startChars) }
    end

    def openStartingTags(startTags, stack, response)
        startTags = startTags.sort_by(&:sort)
        suppressEmit = false
        startTags.each do |tag|
            response.append(tag.startChars) unless suppressEmit
            stack.append(tag)
            # Once we open a code span, any *further* tags opened at the
            # same position get pushed but their start chars are not
            # emitted — they'll be cleaned up by stripStylesInsideCodeSpans.
            suppressEmit = true if tag.startChars.chars.join == "`"
        end
    end

    def emitChar(char, stack, response)
        if insideCodeSpan?(stack)
            response.append(char)
        else
            escaped = Helper.escapeHTML(char.chars.join, isForJekyll)
            response.append(TextChar.new(escaped.chars, "Text"))
        end
    end

    def insideCodeSpan?(stack)
        stack.any? { |tag| tag.startChars.chars.join == "`" }
    end

    # When several tags end at the same position, pop them off the stack
    # in reverse-open order. If the popped tag isn't one of the ones
    # supposed to end here (overlapping markups), close it anyway and
    # re-open it after the legitimate closes — keeping each individual
    # tag pair properly nested in the output.
    def closeEndingTags(endTags, stack, response)
        return if endTags.empty?

        # Caller passes the pre-built bucket; clone so we can mutate locally
        # (find_index + delete_at) without trashing the cached array.
        endTags = endTags.dup

        mismatchTags = []
        until endTags.empty?
            stackTag = stack.pop
            matchIdx = endTags.find_index(stackTag)
            if matchIdx
                endTags.delete_at(matchIdx)
            else
                mismatchTags.append(stackTag)
            end
            response.append(stackTag.endChars)
        end

        mismatchTags.reverse_each do |tag|
            response.append(tag.startChars)
            stack.append(tag)
        end
    end

    # Markdown forbids nested inline styles inside an inline code span —
    # `**bold**` inside `` ` `` would render as literal asterisks. Walk
    # the response and remove any TagStart/TagEnd that lands between a
    # backtick TagStart and TagEnd pair.
    def stripStylesInsideCodeSpans(response)
        loop do
            removed = false
            inCode = false
            response.each_with_index do |char, i|
                text = char.chars.join
                if text == "`"
                    inCode = (char.type == "TagStart")
                    next
                end
                if inCode && (char.type == "TagStart" || char.type == "TagEnd")
                    response.delete_at(i)
                    removed = true
                    break
                end
            end
            break unless removed
        end
    end

    # ESCAPE tags are emitted as TagChar(start: "\\", end: "") — turn the
    # start into a literal `\` text char and drop the empty end. After
    # this pass ESCAPE looks like any other piece of text.
    def flattenEscapeTagsToText(response)
        response.reject! { |c| c.type == "TagEnd" && c.chars.join.empty? }
        response.each_with_index do |c, i|
            if c.type == "TagStart" && c.chars.join == "\\"
                response[i] = TextChar.new("\\".chars, "Text")
            end
        end
    end

    # Three related cleanups, run repeatedly until the stream is stable:
    #   - Drop empty tag pairs (TagStart immediately followed by TagEnd).
    #   - Move whitespace out of the tagged span (no `** bold**`,
    #     no `**bold **`).
    #   - Insert a space after a closing tag when text follows directly,
    #     so `**bold**word` becomes `**bold** word`.
    def tightenSpacingAroundTags(response)
        loop do
            mutated = false

            startTagIndex = nil
            preTag = nil
            preTagIndex = nil
            preTextChar = nil
            preTextIndex = nil

            response.each_with_index do |char, index|
                if preTag&.type == "TagStart" && char.type == "TagEnd"
                    response.delete_at(index)
                    response.delete_at(preTagIndex)
                    mutated = true
                    break
                end

                if char.type == "TagStart" && (preTag.nil? || preTag.type == "TagEnd" || preTag.type == "Text")
                    startTagIndex = index
                elsif (char.type == "TagEnd" || char.type == "Text") && startTagIndex
                    if preTextChar && preTextChar.chars.join != "\n" && preTextChar.chars.join != " "
                        response.insert(startTagIndex, TextChar.new(" ".chars, "Text"))
                        mutated = true
                        break
                    end
                    startTagIndex = nil
                end

                if preTag
                    if preTag.type == "TagStart" && char.type == "Text" && char.chars.join.strip.empty?
                        response.delete_at(index)
                        mutated = true
                        break
                    end

                    if preTag.type == "Text" && char.type == "TagEnd" &&
                       preTextChar && preTextChar.chars.join.strip.empty? && preTextChar.chars.join != "\n"
                        response.delete_at(preTextIndex)
                        mutated = true
                        break
                    end

                    if preTag.type == "TagEnd" && char.type == "Text" && char.chars.join != " "
                        response.insert(index, TextChar.new(" ".chars, "Text"))
                        mutated = true
                        break
                    end
                end

                if char.type == "Text"
                    preTextChar = char
                    preTextIndex = index
                end
                preTag = char
                preTagIndex = index
            end

            break unless mutated
        end
    end
end
