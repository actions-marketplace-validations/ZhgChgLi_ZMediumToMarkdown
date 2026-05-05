require "Parsers/Parser"
require 'Models/Paragraph'

require 'ImageDownloader'
require 'PathPolicy'

class IMGParser < Parser
    attr_accessor :nextParser, :pathPolicy, :isForJekyll

    # When `skipImages: true`, parse() emits the remote miro URL directly
    # without calling ImageDownloader.download or touching pathPolicy.
    # Used by --stdout / --list rendering paths in ZMediumFetcher.
    def initialize(isForJekyll, skipImages: false)
        @isForJekyll = isForJekyll
        @skipImages = skipImages
    end

    def parse(paragraph)
        if paragraph.type == 'IMG'

            fileName = paragraph.metadata.id #d*fsafwfe.jpg

            miro_host = ENV.fetch('MIRO_MEDIUM_HOST', 'https://miro.medium.com')
            imageURL = "#{miro_host}/#{fileName}"

            result = ""
            alt = ""

            if @skipImages
                result = "\r\n\r\n![#{paragraph.text}](#{imageURL}#{alt})\r\n\r\n"
            else
                imagePathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath(paragraph.postID), pathPolicy.getRelativePath(paragraph.postID))
                absolutePath = imagePathPolicy.getAbsolutePath(fileName)

                if  ImageDownloader.download(absolutePath, imageURL)
                    relativePath = imagePathPolicy.getRelativePath(fileName)
                    if isForJekyll
                        result = "\r\n\r\n![#{paragraph.text}](/#{relativePath}#{alt})\r\n\r\n"
                    else
                        result = "\r\n\r\n![#{paragraph.text}](#{relativePath}#{alt})\r\n\r\n"
                    end
                else
                    result = "\r\n\r\n![#{paragraph.text}](#{imageURL}#{alt})\r\n\r\n"
                end
            end

            if paragraph.text != ""
                result += "#{paragraph.text}\r\n"
            end

            result
        else
            if !nextParser.nil?
                nextParser.parse(paragraph)
            end
        end
    end
end
