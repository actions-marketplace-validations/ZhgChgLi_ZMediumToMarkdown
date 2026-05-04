require_relative 'test_helper'

class MarkupStyleRenderTest < Minitest::Test
  def render(text, markups, isForJekyll: false, usersPostURLs: nil)
    p = TestSupport.paragraph(text: text, markups: markups)
    r = MarkupStyleRender.new(p, isForJekyll)
    r.usersPostURLs = usersPostURLs
    r.parse
  end

  def test_plain_text_with_no_markups
    p = TestSupport.paragraph(text: 'plain hello')
    r = MarkupStyleRender.new(p, false)
    assert_equal 'plain hello', r.parse
  end

  def test_strong_renders_double_asterisks
    out = render('hello world', [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    assert_includes out, '**hello**'
  end

  def test_em_renders_underscores
    out = render('hello world', [{ 'type' => 'EM', 'start' => 0, 'end' => 5 }])
    assert_includes out, '_hello_'
  end

  def test_code_renders_backticks
    out = render('inline code', [{ 'type' => 'CODE', 'start' => 0, 'end' => 6 }])
    assert_includes out, '`inline`'
  end

  def test_link_renders_markdown_link
    out = render('go here', [{ 'type' => 'A', 'start' => 0, 'end' => 7, 'href' => 'http://example.com', 'anchorType' => 'LINK' }])
    assert_includes out, '[go here]'
    assert_includes out, '(http://example.com)'
  end

  def test_link_with_jekyll_appends_target_blank
    out = render('go', [{ 'type' => 'A', 'start' => 0, 'end' => 2, 'href' => 'http://example.com', 'anchorType' => 'LINK' }], isForJekyll: true)
    assert_includes out, '{:target="_blank"}'
  end

  def test_user_anchor_uses_medium_user_url
    out = render('mention', [{ 'type' => 'A', 'start' => 0, 'end' => 7, 'anchorType' => 'USER', 'userId' => 'u123' }])
    assert_includes out, '(https://medium.com/u/u123)'
  end

  def test_internal_link_to_known_user_post_uses_relative_path
    users = ['https://medium.com/@me/some-post-deadbeef0001']
    out = render('see this', [{ 'type' => 'A', 'start' => 0, 'end' => 8, 'href' => 'https://medium.com/@me/some-post-deadbeef0001', 'anchorType' => 'LINK' }], usersPostURLs: users)
    # Should produce a relative link to the post slug.
    assert_includes out, '(some-post-deadbeef0001)'
    refute_includes out, 'https://medium.com'
  end

  def test_unknown_markup_type_emits_warning
    out, _err = capture_io do
      @result = render('hi', [{ 'type' => 'WEIRD_TYPE', 'start' => 0, 'end' => 2 }])
    end
    assert_match(/Undefined Markup Type/, out)
    assert_equal 'hi', @result
  end

  def test_optimize_strips_styles_inside_inline_code
    # Markup says: STRONG over the whole word, but it's wrapped in CODE.
    out = render('hello',
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 },
                  { 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    # No double-asterisks should leak into the code span.
    assert_equal '`hello`', out
  end
end
