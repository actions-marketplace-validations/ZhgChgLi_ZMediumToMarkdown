require "Parsers/Parser"
require 'Models/Paragraph'

class ULIParser < Parser
    attr_accessor :nextParser

    def self.isULI(paragraph)
        if paragraph.nil? 
            false
        else
            paragraph.type == "ULI"
        end
    end

    def parse(paragraph)
        if ULIParser.isULI(paragraph)
            "- #{paragraph.text}"
        else
            if !nextParser.nil?
                nextParser.parse(paragraph)
            end
        end
    end
end
