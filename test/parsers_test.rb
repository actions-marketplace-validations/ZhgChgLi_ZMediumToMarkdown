require_relative 'test_helper'

class HeadingParsersTest < Minitest::Test
  def test_h1
    assert_equal '# title', H1Parser.new.parse(TestSupport.paragraph(type: 'H1', text: 'title'))
  end

  def test_h2
    assert_equal '## title', H2Parser.new.parse(TestSupport.paragraph(type: 'H2', text: 'title'))
  end

  def test_h3
    assert_equal '### title', H3Parser.new.parse(TestSupport.paragraph(type: 'H3', text: 'title'))
  end

  def test_h4
    assert_equal '#### title', H4Parser.new.parse(TestSupport.paragraph(type: 'H4', text: 'title'))
  end

  def test_falls_through_to_next_when_type_mismatches
    h1 = H1Parser.new
    fallback = Object.new
    def fallback.parse(p); "FALLBACK:#{p.text}"; end
    h1.setNext(fallback)
    assert_equal 'FALLBACK:hi', h1.parse(TestSupport.paragraph(type: 'P', text: 'hi'))
  end

  def test_returns_nil_when_no_next
    assert_nil H1Parser.new.parse(TestSupport.paragraph(type: 'P', text: 'hi'))
  end
end

class PParserTest < Minitest::Test
  def test_p_prepends_newline
    assert_equal "\nhello", PParser.new.parse(TestSupport.paragraph(type: 'P', text: 'hello'))
  end

  def test_type_string_helper
    assert_equal 'P', PParser.getTypeString
  end
end

class ULIParserTest < Minitest::Test
  def test_uli_renders_dash_prefix
    assert_equal '- foo', ULIParser.new.parse(TestSupport.paragraph(type: 'ULI', text: 'foo'))
  end

  def test_is_uli_predicate
    assert ULIParser.isULI(TestSupport.paragraph(type: 'ULI'))
    refute ULIParser.isULI(TestSupport.paragraph(type: 'P'))
    refute ULIParser.isULI(nil)
  end
end

class OLIParserTest < Minitest::Test
  def test_oli_renders_index_prefix
    p = TestSupport.paragraph(type: 'OLI', text: 'foo')
    p.oliIndex = 3
    assert_equal '3. foo', OLIParser.new.parse(p)
  end

  def test_is_oli_predicate
    assert OLIParser.isOLI(TestSupport.paragraph(type: 'OLI'))
    refute OLIParser.isOLI(nil)
  end
end

class BQParserTest < Minitest::Test
  def test_bq_renders_quote_prefix_per_line
    p = TestSupport.paragraph(type: 'BQ', text: "line1\nline2")
    out = BQParser.new.parse(p)
    assert_includes out, '> line1'
    assert_includes out, '> line2'
  end
end

class PQParserTest < Minitest::Test
  def test_pq_renders_quote_prefix
    p = TestSupport.paragraph(type: 'PQ', text: "quote")
    out = PQParser.new.parse(p)
    assert_includes out, '> quote'
  end
end

class PREParserTest < Minitest::Test
  def test_pre_wraps_in_code_fence_with_lang
    p = TestSupport.paragraph(type: 'PRE', text: "puts 'hi'", codeBlockMetadata: { 'lang' => 'ruby' })
    out = PREParser.new(false).parse(p)
    assert_equal "```ruby\nputs 'hi'\n```", out
  end

  def test_pre_without_lang
    p = TestSupport.paragraph(type: 'PRE', text: 'plain code')
    out = PREParser.new(false).parse(p)
    assert_equal "```\nplain code\n```", out
  end

  def test_is_pre_predicate
    assert PREParser.isPRE(TestSupport.paragraph(type: 'PRE'))
    refute PREParser.isPRE(nil)
  end
end

class CodeBlockParserTest < Minitest::Test
  def test_code_block_wraps_in_unlabeled_fence
    p = TestSupport.paragraph(type: CodeBlockParser.getTypeString, text: "a\nb")
    out = CodeBlockParser.new(false).parse(p)
    assert_equal "```\na\nb\n```", out
  end

  def test_is_code_block_predicate
    assert CodeBlockParser.isCodeBlock(TestSupport.paragraph(type: CodeBlockParser.getTypeString))
    refute CodeBlockParser.isCodeBlock(nil)
  end
end

class FallbackParserTest < Minitest::Test
  def test_returns_text_and_warns
    p = TestSupport.paragraph(type: 'WEIRD', text: 'plain')
    out = capture_io { @result = FallbackParser.new.parse(p) }
    assert_equal 'plain', @result
    assert_match(/WARNING/, out.first)
  end
end

class MIXTAPEEMBEDParserTest < Minitest::Test
  def test_mixtape_falls_back_to_text_when_no_metadata
    p = TestSupport.paragraph(type: 'MIXTAPE_EMBED', text: 'fallback')
    out = MIXTAPEEMBEDParser.new(false).parse(p)
    assert_equal "\nfallback", out
  end

  def test_mixtape_renders_image_when_og_image_available
    p = TestSupport.paragraph(type: 'MIXTAPE_EMBED', text: 'fallback', mixtapeMetadata: { 'href' => 'http://example.com' })
    Helper.stub(:fetchOGImage, 'http://example.com/img.png') do
      out = MIXTAPEEMBEDParser.new(true).parse(p)
      assert_includes out, '[![](http://example.com/img.png)]'
      assert_includes out, '(http://example.com)'
      assert_includes out, '{:target="_blank"}'
    end
  end

  def test_mixtape_falls_back_to_text_when_og_empty
    p = TestSupport.paragraph(type: 'MIXTAPE_EMBED', text: 'fallback', mixtapeMetadata: { 'href' => 'http://example.com' })
    Helper.stub(:fetchOGImage, '') do
      out = MIXTAPEEMBEDParser.new(false).parse(p)
      assert_equal "\nfallback", out
    end
  end
end
