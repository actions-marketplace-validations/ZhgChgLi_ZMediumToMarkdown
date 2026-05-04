require_relative 'test_helper'

class MarkupParserTest < Minitest::Test
  def test_returns_text_unchanged_when_no_markups
    p = TestSupport.paragraph(text: 'hello')
    p.markups = []
    assert_equal 'hello', MarkupParser.new(p, false).parse
  end

  def test_returns_text_unchanged_when_markups_nil
    p = TestSupport.paragraph(text: 'hello')
    p.markups = nil
    assert_equal 'hello', MarkupParser.new(p, false).parse
  end

  def test_delegates_to_style_render_when_markups_present
    p = TestSupport.paragraph(text: 'hello',
                              markups: [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    out = MarkupParser.new(p, false).parse
    assert_includes out, '**hello**'
  end

  def test_swallows_render_errors_with_warning
    p = TestSupport.paragraph(text: 'hello',
                              markups: [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    parser = MarkupParser.new(p, false)
    fake = Object.new
    def fake.usersPostURLs=(_); end
    def fake.parse; raise 'boom'; end
    MarkupStyleRender.stub(:new, fake) do
      out, _err = capture_io { @result = parser.parse }
      assert_match(/Error occurred during render markup text/, out)
      # Should fall back to the original text.
      assert_equal 'hello', @result
    end
  end
end
