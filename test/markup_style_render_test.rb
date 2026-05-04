require_relative 'test_helper'

class MarkupStyleRenderTest < Minitest::Test
  def render(text, markups, isForJekyll: false, usersPostURLs: nil)
    p = TestSupport.paragraph(text: text, markups: markups)
    r = MarkupStyleRender.new(p, isForJekyll)
    r.usersPostURLs = usersPostURLs
    r.parse
  end

  # ----- basic markup rendering -----

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

  # ----- ESCAPE markup -----
  # Use `-` as the target char: it only auto-escapes at paragraph-start
  # (position 0), so at position 1 the only ESCAPE markup is the one we
  # add explicitly. This isolates the render-layer behavior from the
  # auto-escape injection in Paragraph#initialize.

  def test_escape_markup_inserts_backslash_before_char
    out = render('a-b', [{ 'type' => 'ESCAPE', 'start' => 1, 'end' => 2 }])
    assert_includes out, 'a\\-b'
  end

  def test_escape_markup_combines_with_inline_styles
    out = render('a-b', [
      { 'type' => 'STRONG', 'start' => 0, 'end' => 3 },
      { 'type' => 'ESCAPE', 'start' => 1, 'end' => 2 }
    ])
    assert_includes out, '**a\\-b**'
  end

  # ----- code-span optimization -----

  def test_optimize_strips_styles_inside_inline_code
    out = render('hello',
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 },
                  { 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    assert_equal '`hello`', out
  end

  def test_optimize_strips_em_inside_code_span
    out = render('hello world',
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 11 },
                  { 'type' => 'EM',   'start' => 6, 'end' => 11 }])
    assert_equal '`hello world`', out
  end

  def test_html_chars_inside_code_span_are_not_escaped
    # Inside a code span, `<` `>` should pass through literally — the
    # render layer skips Helper.escapeHTML for chars wrapped in backticks.
    out = render('<tag>', [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 }])
    assert_equal '`<tag>`', out
  end

  def test_html_chars_outside_code_span_get_backslash_escaped_with_markup
    # When the paragraph has any markup, Helper.escapeHTML runs per-char
    # in the render walk. Default (non-Jekyll) mode produces \< \>.
    out = render('a<x>', [{ 'type' => 'STRONG', 'start' => 0, 'end' => 1 }])
    assert_includes out, '\\<x\\>'
  end

  def test_html_chars_outside_code_span_get_entity_with_markup_in_jekyll
    out = render('a<x>', [{ 'type' => 'STRONG', 'start' => 0, 'end' => 1 }], isForJekyll: true)
    assert_includes out, '&lt;x&gt;'
  end

  # ----- tag spacing optimization -----

  def test_optimize_drops_trailing_space_inside_strong_span
    # STRONG covers "hello " (trailing space). The optimizer should pull the
    # space out so the closing ** sits flush against "hello".
    out = render('hello world', [{ 'type' => 'STRONG', 'start' => 0, 'end' => 6 }])
    assert_includes out, '**hello**'
    refute_includes out, '**hello **'
  end

  def test_optimize_drops_leading_space_inside_em_span
    out = render('a bcd', [{ 'type' => 'EM', 'start' => 1, 'end' => 4 }])
    # Leading space inside `_ bc_` should be moved out: `a _bc_d`.
    assert_includes out, '_bc_'
    refute_includes out, '_ bc'
  end

  def test_optimize_inserts_space_after_closing_tag_when_text_follows
    # Ensures `**bold**word` becomes `**bold** word` so adjacent text doesn't
    # cling to the closing tag.
    out = render('boldword', [{ 'type' => 'STRONG', 'start' => 0, 'end' => 4 }])
    assert_includes out, '**bold** word'
  end

  # ----- line-break handling -----

  def test_strong_span_across_newline_closes_and_reopens
    # STRONG covers "ab\ncd". The render layer must close ** at the \n and
    # reopen on the next line, otherwise the markdown source breaks across
    # the line and the second line isn't bolded. (Optimize may inject a
    # trailing space after the first **; tolerate it.)
    out = render("ab\ncd", [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    lines = out.split("\n")
    assert_equal 2, lines.length
    assert_match(/^\*\*ab\*\*\s*$/, lines[0])
    assert_match(/^\*\*cd\*\*$/, lines[1])
  end

  def test_plain_text_with_newline_passes_through
    p = TestSupport.paragraph(text: "line1\nline2")
    r = MarkupStyleRender.new(p, false)
    assert_equal "line1\nline2", r.parse
  end

  # ----- multi-byte / emoji positioning -----

  def test_emoji_position_indices_count_two
    # Emoji takes two positions in Medium's index space; "x😀y" maps to
    # x=0, emoji=1+2, y=3 — so STRONG covering the whole thing is end=4.
    out = render("x\u{1F600}y", [{ 'type' => 'STRONG', 'start' => 0, 'end' => 4 }])
    assert_includes out, "**x\u{1F600}y**"
  end

  # ----- ordering / nesting -----

  def test_strong_with_inner_em_renders_nested
    out = render('hello world',
                 [{ 'type' => 'STRONG', 'start' => 0, 'end' => 11 },
                  { 'type' => 'EM',     'start' => 6, 'end' => 11 }])
    assert_includes out, '**hello _world_**'
  end

  def test_link_with_inner_strong
    out = render('click here',
                 [{ 'type' => 'A',      'start' => 0, 'end' => 10, 'href' => 'http://e.co', 'anchorType' => 'LINK' },
                  { 'type' => 'STRONG', 'start' => 0, 'end' => 5 }])
    assert_includes out, '[**click**'
    assert_includes out, '](http://e.co)'
  end

  def test_link_url_with_invalid_format_is_skipped
    # Markup A with an href that doesn't match the http(s) URL regex falls
    # through silently — no anchor tag is emitted, text is plain.
    out = render('hello', [{ 'type' => 'A', 'start' => 0, 'end' => 5, 'href' => 'notaurl', 'anchorType' => 'LINK' }])
    assert_equal 'hello', out
  end

  # ----- markup boundary cases (intersection / union / adjacent / equal) -----
  # The render layer has to cope with overlapping markup spans because Medium
  # serializes them per-character without enforcing nesting. These tests pin
  # down the current behavior so future refactors keep it stable.

  TEXT11 = 'hello world'.freeze # length 11; positions 0..10

  # --- containment (one fully wraps the other) ---

  def test_code_containing_em_strips_em_tags
    # CODE forbids inline style; EM tags inside the code span are dropped.
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 11 },
                  { 'type' => 'EM',   'start' => 6, 'end' => 11 }])
    assert_equal '`hello world`', out
  end

  def test_code_containing_em_at_start_strips_em
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 11 },
                  { 'type' => 'EM',   'start' => 2, 'end' => 5 }])
    assert_equal '`hello world`', out
  end

  def test_em_containing_code_keeps_both
    # EM wraps the whole text; the inner CODE span is preserved. Note the
    # current spacing pass injects spaces around the inner code span.
    out = render(TEXT11,
                 [{ 'type' => 'EM',   'start' => 0, 'end' => 11 },
                  { 'type' => 'CODE', 'start' => 3, 'end' => 8 }])
    assert_equal '_hel `lo wo` rld_', out
  end

  def test_strong_containing_em_renders_nested
    out = render(TEXT11,
                 [{ 'type' => 'STRONG', 'start' => 0, 'end' => 11 },
                  { 'type' => 'EM',     'start' => 6, 'end' => 11 }])
    assert_equal '**hello _world_**', out
  end

  # --- partial overlap (intersection) ---

  def test_code_then_em_with_partial_overlap_strips_overlap
    # CODE[0..5], EM[3..8] — EM's first 2 covered chars sit inside CODE
    # and are stripped; the remainder of EM lives outside.
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 },
                  { 'type' => 'EM',   'start' => 3, 'end' => 8 }])
    assert_equal '`hello` _wo_ rld', out
  end

  def test_em_then_code_with_partial_overlap_reorders_close
    # EM[0..5], CODE[3..8] — when EM ends at 4, CODE is still open, so
    # the walker closes CODE early (mismatch), closes EM, then reopens
    # CODE for the rest of its span.
    out = render(TEXT11,
                 [{ 'type' => 'EM',   'start' => 0, 'end' => 5 },
                  { 'type' => 'CODE', 'start' => 3, 'end' => 8 }])
    assert_equal '_hel `lo`_ `wo` rld', out
  end

  def test_strong_and_em_with_partial_overlap_reorders_close
    out = render(TEXT11,
                 [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 },
                  { 'type' => 'EM',     'start' => 3, 'end' => 8 }])
    # STRONG closes at 4; EM extends to 7. Walker emits EM close, STRONG
    # close, then re-opens EM for the remainder.
    assert_equal '**hel _lo_** _wo_ rld', out
  end

  # --- adjacent (one ends exactly where the next starts) ---

  def test_code_immediately_followed_by_em_keeps_both
    # CODE ends at 5 (last covered = 4); EM opens at 5. They share no chars.
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 },
                  { 'type' => 'EM',   'start' => 5, 'end' => 10 }])
    assert_equal '`hello` _worl_ d', out
  end

  # --- disjoint (gap between spans) ---

  def test_disjoint_code_and_em_render_independently
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 3 },
                  { 'type' => 'EM',   'start' => 5, 'end' => 10 }])
    assert_equal '`hel` lo _worl_ d', out
  end

  # --- identical spans (same start, same end) ---

  def test_code_and_em_on_identical_span_keeps_only_code
    # CODE wins; the EM tags get stripped because they sit inside the code span.
    out = render(TEXT11,
                 [{ 'type' => 'CODE', 'start' => 0, 'end' => 5 },
                  { 'type' => 'EM',   'start' => 0, 'end' => 5 }])
    assert_equal '`hello` world', out
  end

  def test_strong_and_em_on_identical_span_renders_combined
    out = render(TEXT11,
                 [{ 'type' => 'STRONG', 'start' => 0, 'end' => 5 },
                  { 'type' => 'EM',     'start' => 0, 'end' => 5 }])
    # Both tags fire on the same range. Sort priority puts STRONG/EM
    # together (sort=2); the actual emission order depends on input order.
    assert_includes out, '**'
    assert_includes out, '_'
    assert_includes out, 'hello'
  end
end
