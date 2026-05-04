$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'minitest/autorun'

# Cookie jar referenced by Request; required to be defined before Request loads.
$cookies ||= {}

require 'PathPolicy'
require 'Helper'
require 'Post'
require 'User'
require 'Models/Paragraph'
require 'Parsers/Parser'
require 'Parsers/H1Parser'
require 'Parsers/H2Parser'
require 'Parsers/H3Parser'
require 'Parsers/H4Parser'
require 'Parsers/PParser'
require 'Parsers/ULIParser'
require 'Parsers/OLIParser'
require 'Parsers/BQParser'
require 'Parsers/PQParser'
require 'Parsers/PREParser'
require 'Parsers/CodeBlockParser'
require 'Parsers/IMGParser'
require 'Parsers/IframeParser'
require 'Parsers/MIXTAPEEMBEDParser'
require 'Parsers/FallbackParser'
require 'Parsers/MarkupParser'
require 'Parsers/MarkupStyleRender'
require 'ZMediumFetcher'
require 'CLI'

module TestSupport
  POST_ID = 'abcdef123456'.freeze

  # Build a Paragraph quickly from a small JSON-ish hash.
  def self.paragraph(overrides = {})
    json = {
      'name' => "p_#{rand(10_000)}",
      'text' => '',
      'type' => 'P'
    }.merge(overrides.transform_keys(&:to_s))
    Paragraph.new(json, POST_ID)
  end
end
