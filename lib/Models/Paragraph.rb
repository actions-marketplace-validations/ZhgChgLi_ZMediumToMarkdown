require 'Helper'
require 'Parsers/PParser'
require 'securerandom'

class Paragraph
    attr_accessor :postID, :name, :orgText, :text, :type, :href, :metadata, :mixtapeMetadata, :iframe, :oliIndex, :markups, :markupLinks, :codeBlockMetadata


    class Iframe
        attr_accessor :id, :title, :type, :src
        def initialize(json)
            @id = json['id']
            @type = json['__typename']
            @title = json['title']
            @src = json['iframeSrc']
        end
    end

    class Markup
        attr_accessor :type, :start, :end, :href, :anchorType, :userId, :linkMetadata

        # Semantic identity fields used for `==` / `eql?` / `hash`. `start` and
        # `end` are interval coordinates (handled by Rangeable as the [lo, hi]
        # pair) rather than identity. `linkMetadata` is currently unused
        # downstream so it is excluded too. This identity is what lets
        # Rangeable merge two Markups that describe the same logical span
        # (e.g. two STRONG runs that overlap) into a single coalesced
        # interval.
        SEMANTIC_KEYS = [:type, :href, :anchorType, :userId].freeze

        def initialize(json)
            @type = json['type']
            @start = json['start']
            @end = json['end']
            @href = json['href']
            @anchorType = json['anchorType']
            @userId = json['userId']
            @linkMetadata = json['linkMetadata']
        end

        def ==(other)
            return false unless other.is_a?(Markup)
            SEMANTIC_KEYS.all? { |k| public_send(k) == other.public_send(k) }
        end
        alias_method :eql?, :==

        def hash
            SEMANTIC_KEYS.map { |k| public_send(k) }.hash
        end
    end

    class MetaData
        attr_accessor :id, :type
        def initialize(json)
            @id = json['id']
            @type = json['__typename']
        end
    end

    class MixtapeMetadata
        attr_accessor :href
        def initialize(json)
            @href = json['href']
        end
    end

    class CodeBlockMetadata
        attr_accessor :lang
        def initialize(json)
            @lang = json['lang']
        end
    end

    def self.makeBlankParagraph(postID)
        json = {
            "name" => "fakeBlankParagraph_#{SecureRandom.uuid}",
            "text" => "",
            "type" => PParser.getTypeString()
        }
        Paragraph.new(json, postID)
    end

    def initialize(json, postID)
        @name = json['name']
        @text = json['text']
        @orgText = json['text']
        @type = json['type']
        @href = json['href']
        @postID = postID

        if json['metadata'].nil?
            @metadata = nil
        else
            @metadata = MetaData.new(json['metadata'])
        end

        if json['codeBlockMetadata'].nil?
            @codeBlockMetadata = nil
        else
            @codeBlockMetadata = CodeBlockMetadata.new(json['codeBlockMetadata'])
        end

        if json['mixtapeMetadata'].nil?
            @mixtapeMetadata = nil
        else
            @mixtapeMetadata = MixtapeMetadata.new(json['mixtapeMetadata'])
        end

        if json['iframe'].nil? || !json['iframe'] || !json['iframe']['mediaResource']
            @iframe = nil
        else
            @iframe = Iframe.new(json['iframe']['mediaResource'])
        end
        
        markups = []
        if !json['markups'].nil? && json['markups'].length > 0
            json['markups'].each do |markup|
                markups.append(Markup.new(markup))
            end
            
            links = json['markups'].select{ |markup| markup["type"] == "A" }
            if !links.nil? && links.length > 0
                @markupLinks = links.map{ |link| link["href"] }
            end
        end

        # Walk every char in the paragraph text and inject synthetic ESCAPE
        # markups for chars that would otherwise be re-interpreted as markdown.
        # `precedingChars` is needed by Helper.markdownEscapeNeeded? to detect
        # block-level markers at paragraph start (e.g. `# heading`, `1. item`).
        index = 0
        precedingChars = []
        orgText.each_char do |char|
            if Helper.markdownEscapeNeeded?(char, precedingChars)
                markups.append(Markup.new(
                    "type" => 'ESCAPE',
                    "start" => index,
                    "end" => index + 1
                ))
            end
            precedingChars << char

            index += 1
            if char.bytes.length >= 4
                # some emoji take an extra position in Medium's index space
                index += 1
            end
        end

        @markups = markups
    end
end