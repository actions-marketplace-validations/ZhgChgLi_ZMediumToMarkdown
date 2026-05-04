require_relative 'test_helper'
require 'nokogiri'

class PostTest < Minitest::Test
  def test_get_post_id_from_url
    url = 'https://medium.com/@user/some-cool-post-abcdef123456'
    assert_equal 'abcdef123456', Post.getPostIDFromPostURLString(url)
  end

  def test_get_post_id_from_publication_url
    url = 'https://medium.com/publication/another-one-deadbeef0001?source=foo'
    assert_equal 'deadbeef0001', Post.getPostIDFromPostURLString(url)
  end

  def test_get_post_path_returns_last_segment
    url = 'https://medium.com/@user/some-cool-post-abcdef123456'
    assert_equal 'some-cool-post-abcdef123456', Post.getPostPathFromPostURLString(url)
  end

  def test_parse_post_content_from_nil_html_returns_nil
    # Critical: must return nil, not "" — callers check `.nil?`.
    assert_nil Post.parsePostContentFromHTML(nil)
  end

  def test_parse_post_content_extracts_apollo_state
    html = Nokogiri::HTML(<<~HTML)
      <html><body>
        <script>window.__APOLLO_STATE__ = {"hello":"world"}</script>
      </body></html>
    HTML
    parsed = Post.parsePostContentFromHTML(html)
    assert_equal({ 'hello' => 'world' }, parsed)
  end

  def test_parse_post_content_returns_nil_when_apollo_missing
    html = Nokogiri::HTML('<html><body><script>console.log(1)</script></body></html>')
    assert_nil Post.parsePostContentFromHTML(html)
  end

  def test_parse_post_info_returns_blank_postinfo_when_content_nil
    info = Post.parsePostInfoFromPostContent(nil, 'pid', PathPolicy.new('/abs', 'rel'))
    assert_instance_of Post::PostInfo, info
    assert_nil info.title
    assert_nil info.tags
  end

  def test_parse_post_info_returns_blank_postinfo_when_post_missing
    info = Post.parsePostInfoFromPostContent({}, 'pid', PathPolicy.new('/abs', 'rel'))
    assert_nil info.title
  end

  def test_parse_post_info_extracts_fields
    content = {
      'Post:pid' => {
        'title'             => 'Hello',
        'previewContent'    => { 'subtitle' => 'sub' },
        'tags'              => [{ '__ref' => 'Tag:ruby' }, { '__ref' => 'Tag:medium' }],
        'creator'           => { '__ref' => 'User:1' },
        'collection'        => { '__ref' => 'Coll:9' },
        'firstPublishedAt'  => 1_700_000_000_000,
        'latestPublishedAt' => 1_700_000_500_000
      },
      'User:1' => { 'name' => 'Z' },
      'Coll:9' => { 'name' => 'Tech' }
    }
    info = Post.parsePostInfoFromPostContent(content, 'pid', PathPolicy.new('/abs', 'rel'))
    assert_equal 'Hello', info.title
    assert_equal 'sub',   info.description
    assert_equal ['ruby', 'medium'], info.tags
    assert_equal 'Z',    info.creator
    assert_equal 'Tech', info.collectionName
    assert_kind_of Time, info.firstPublishedAt
    assert_kind_of Time, info.latestPublishedAt
  end

  def test_parse_post_info_strips_non_printable_characters
    # \x07 (BEL) is a control character that the [^[:print:]] regex strips.
    content = {
      'Post:pid' => {
        'title'          => "Hi\x07!",
        'previewContent' => { 'subtitle' => "x\x07y" },
        'tags'           => []
      }
    }
    info = Post.parsePostInfoFromPostContent(content, 'pid', PathPolicy.new('/abs', 'rel'))
    assert_equal 'Hi!', info.title
    assert_equal 'xy',  info.description
  end
end
