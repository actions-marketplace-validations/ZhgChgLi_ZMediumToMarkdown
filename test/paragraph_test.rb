require_relative 'test_helper'

class ParagraphTest < Minitest::Test
  def test_basic_initialization
    p = TestSupport.paragraph(text: 'hello', type: 'P', name: 'p1')
    assert_equal 'hello', p.text
    assert_equal 'hello', p.orgText
    assert_equal 'P',     p.type
    assert_equal 'p1',    p.name
    assert_equal TestSupport::POST_ID, p.postID
  end

  def test_make_blank_paragraph_has_unique_name
    a = Paragraph.makeBlankParagraph('pid')
    b = Paragraph.makeBlankParagraph('pid')
    assert_equal '', a.text
    assert_equal 'P', a.type
    refute_equal a.name, b.name
    assert a.name.start_with?('fakeBlankParagraph_')
  end

  def test_metadata_subobject_is_built_when_present
    p = TestSupport.paragraph(metadata: { 'id' => 'img.jpg', '__typename' => 'ImageMetadata' })
    assert_equal 'img.jpg', p.metadata.id
    assert_equal 'ImageMetadata', p.metadata.type
  end

  def test_metadata_is_nil_when_absent
    p = TestSupport.paragraph
    assert_nil p.metadata
  end

  def test_iframe_subobject_is_built_when_media_resource_present
    p = TestSupport.paragraph(iframe: { 'mediaResource' => { 'id' => 'i', 'iframeSrc' => 'http://x', 'title' => 't' } })
    refute_nil p.iframe
    assert_equal 'i',       p.iframe.id
    assert_equal 'http://x', p.iframe.src
    assert_equal 't',       p.iframe.title
  end

  def test_iframe_is_nil_when_media_resource_missing
    p = TestSupport.paragraph(iframe: {})
    assert_nil p.iframe
  end

  def test_markups_collected_and_links_extracted
    p = TestSupport.paragraph(
      text: 'hello',
      markups: [
        { 'type' => 'STRONG', 'start' => 0, 'end' => 5 },
        { 'type' => 'A',      'start' => 0, 'end' => 5, 'href' => 'http://x' }
      ]
    )
    types = p.markups.map(&:type)
    assert_includes types, 'STRONG'
    assert_includes types, 'A'
    assert_equal ['http://x'], p.markupLinks
  end

  def test_escape_markups_inserted_for_special_chars
    p = TestSupport.paragraph(text: 'a*b')
    escapes = p.markups.select { |m| m.type == 'ESCAPE' }
    assert_equal 1, escapes.length
    assert_equal 1, escapes.first.start
    assert_equal 2, escapes.first.end
  end

  def test_emoji_advances_index_by_two
    p = TestSupport.paragraph(text: "x\u{1F600}*")
    escape = p.markups.find { |m| m.type == 'ESCAPE' }
    refute_nil escape
    # 'x' is index 0, emoji takes indexes 1+2, so '*' lands at 3.
    assert_equal 3, escape.start
  end
end
