require_relative 'test_helper'
require 'json'

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

  def test_parse_post_info_returns_nil_when_request_fails
    Request.stub(:URL, nil) do
      Request.stub(:body, nil) do
        assert_nil Post.parsePostInfo('pid', PathPolicy.new('/abs', 'rel'))
      end
    end
  end

  def test_parse_post_info_returns_nil_when_postresult_missing
    Request.stub(:URL, nil) do
      Request.stub(:body, JSON.dump([{ 'data' => {} }])) do
        assert_nil Post.parsePostInfo('pid', PathPolicy.new('/abs', 'rel'))
      end
    end
  end

  def test_parse_post_info_extracts_fields
    payload = [{
      'data' => {
        'postResult' => {
          'title'             => 'Hello',
          'previewContent'    => { 'subtitle' => 'sub' },
          'tags'              => [{ 'normalizedTagSlug' => 'ruby' }, { 'normalizedTagSlug' => 'medium' }],
          'creator'           => { 'name' => 'Z' },
          'collection'        => { 'name' => 'Tech' },
          'firstPublishedAt'  => 1_700_000_000_000,
          'latestPublishedAt' => 1_700_000_500_000
        }
      }
    }]
    Request.stub(:URL, nil) do
      Request.stub(:body, JSON.dump(payload)) do
        info = Post.parsePostInfo('pid', PathPolicy.new('/abs', 'rel'))
        assert_equal 'Hello', info.title
        assert_equal 'sub',   info.description
        assert_equal ['ruby', 'medium'], info.tags
        assert_equal 'Z',    info.creator
        assert_equal 'Tech', info.collectionName
        assert_kind_of Time, info.firstPublishedAt
        assert_kind_of Time, info.latestPublishedAt
      end
    end
  end

  def test_parse_post_info_strips_non_printable_characters
    # \x07 (BEL) is a control character that the [^[:print:]] regex strips.
    payload = [{
      'data' => {
        'postResult' => {
          'title'          => "Hi\x07!",
          'previewContent' => { 'subtitle' => "x\x07y" },
          'tags'           => []
        }
      }
    }]
    Request.stub(:URL, nil) do
      Request.stub(:body, JSON.dump(payload)) do
        info = Post.parsePostInfo('pid', PathPolicy.new('/abs', 'rel'))
        assert_equal 'Hi!', info.title
        assert_equal 'xy',  info.description
      end
    end
  end
end
