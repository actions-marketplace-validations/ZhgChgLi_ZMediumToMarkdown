require_relative 'test_helper'

class TwitterEmbedTokenTest < Minitest::Test
  def test_generates_non_empty_alphanumeric_token
    token = TwitterEmbed.generateToken('1234567890123456789')
    assert_kind_of String, token
    refute_empty token
    refute_includes token, '0'
    refute_includes token, '.'
    assert_match(/\A[a-z0-9]+\z/, token)
  end

  def test_token_is_deterministic_for_same_id
    a = TwitterEmbed.generateToken('1700000000000000000')
    b = TwitterEmbed.generateToken('1700000000000000000')
    assert_equal a, b
  end

  def test_token_differs_for_different_ids
    a = TwitterEmbed.generateToken('1700000000000000000')
    b = TwitterEmbed.generateToken('1800000000000000000')
    refute_equal a, b
  end
end

class TwitterEmbedRenderTest < Minitest::Test
  def base_tweet
    {
      'text' => 'hello world',
      'user' => { 'name' => 'Alice', 'screen_name' => 'alice' },
      'created_at' => '2024-01-15T10:30:00.000Z',
      'entities' => { 'user_mentions' => [], 'urls' => [] }
    }
  end

  def test_renders_blockquote_with_author_text_and_date
    md = TwitterEmbed.renderMarkdown(base_tweet, 'https://twitter.com/alice/status/1', jekyllOpen: '')
    assert_includes md, '[Alice](https://twitter.com/alice)'
    assert_includes md, '@ Twitter Says:'
    assert_includes md, '> > hello world'
    assert_includes md, 'Tweeted at [2024-01-15 10:30:00](https://twitter.com/alice/status/1)'
    assert_includes md, '■■■■■■■■■■■■■■'
  end

  def test_falls_back_to_screen_name_when_display_name_missing
    tweet = base_tweet.merge('user' => { 'screen_name' => 'alice' })
    md = TwitterEmbed.renderMarkdown(tweet, 'https://twitter.com/alice/status/1', jekyllOpen: '')
    assert_includes md, '[alice](https://twitter.com/alice)'
  end

  def test_returns_nil_for_non_hash_input
    assert_nil TwitterEmbed.renderMarkdown(nil, 'http://x', jekyllOpen: '')
    assert_nil TwitterEmbed.renderMarkdown('oops', 'http://x', jekyllOpen: '')
  end

  def test_appends_jekyll_target_blank_marker
    md = TwitterEmbed.renderMarkdown(base_tweet, 'https://twitter.com/alice/status/1', jekyllOpen: '{:target="_blank"}')
    # Both author link and date link should carry the marker.
    assert_equal 2, md.scan('{:target="_blank"}').size
  end

  def test_handles_invalid_created_at_gracefully
    tweet = base_tweet.merge('created_at' => 'not-a-date')
    md = TwitterEmbed.renderMarkdown(tweet, 'http://t/1', jekyllOpen: '')
    # Falls back to the raw value instead of raising.
    assert_includes md, 'not-a-date'
  end

  def test_handles_blank_created_at
    tweet = base_tweet.merge('created_at' => nil)
    md = TwitterEmbed.renderMarkdown(tweet, 'http://t/1', jekyllOpen: '')
    refute_nil md
  end
end

class TwitterEmbedEntityExpansionTest < Minitest::Test
  def test_expands_user_mentions_into_markdown_links
    tweet = {
      'text' => 'hi @bob and charlie',
      'entities' => {
        'user_mentions' => [
          { 'screen_name' => 'bob' },
          { 'screen_name' => 'charlie' }
        ],
        'urls' => []
      }
    }
    out = TwitterEmbed.expandEntities(tweet)
    assert_includes out, '@[bob](https://twitter.com/bob)'
    assert_includes out, '[charlie](https://twitter.com/charlie)'
  end

  def test_expands_short_urls_with_display_label
    tweet = {
      'text' => 'see https://t.co/abc for more',
      'entities' => {
        'user_mentions' => [],
        'urls' => [
          { 'url' => 'https://t.co/abc', 'display_url' => 'example.com/page', 'expanded_url' => 'https://example.com/page' }
        ]
      }
    }
    out = TwitterEmbed.expandEntities(tweet)
    assert_includes out, '[example.com/page](https://example.com/page)'
    refute_includes out, 'https://t.co/abc'
  end

  def test_falls_back_to_expanded_url_when_display_url_missing
    tweet = {
      'text' => 'see https://t.co/abc',
      'entities' => {
        'user_mentions' => [],
        'urls' => [
          { 'url' => 'https://t.co/abc', 'expanded_url' => 'https://example.com' }
        ]
      }
    }
    out = TwitterEmbed.expandEntities(tweet)
    assert_includes out, '[https://example.com](https://example.com)'
  end

  def test_handles_missing_entities_dict
    tweet = { 'text' => 'plain text' }
    assert_equal 'plain text', TwitterEmbed.expandEntities(tweet)
  end

  def test_skips_blank_or_nil_entries
    tweet = {
      'text' => 'plain',
      'entities' => {
        'user_mentions' => [{ 'screen_name' => nil }, {}],
        'urls' => [{ 'url' => '' }, { 'url' => nil }]
      }
    }
    assert_equal 'plain', TwitterEmbed.expandEntities(tweet)
  end
end

class TwitterEmbedFetchTest < Minitest::Test
  def test_fetch_returns_nil_when_request_body_is_nil
    Request.stub(:URL, nil) do
      Request.stub(:body, nil) do
        assert_nil TwitterEmbed.fetch('1234567890123456789')
      end
    end
  end

  def test_fetch_returns_nil_when_body_is_empty_string
    Request.stub(:URL, nil) do
      Request.stub(:body, '') do
        assert_nil TwitterEmbed.fetch('1234567890123456789')
      end
    end
  end

  def test_fetch_returns_nil_on_invalid_json
    Request.stub(:URL, nil) do
      Request.stub(:body, 'not-json{') do
        assert_nil TwitterEmbed.fetch('1234567890123456789')
      end
    end
  end

  def test_fetch_parses_valid_json_body
    json = '{"text":"hi","user":{"name":"A","screen_name":"a"}}'
    Request.stub(:URL, nil) do
      Request.stub(:body, json) do
        out = TwitterEmbed.fetch('1234567890123456789')
        assert_equal 'hi', out['text']
        assert_equal 'a', out.dig('user', 'screen_name')
      end
    end
  end

  def test_render_falls_back_to_nil_when_fetch_fails
    Request.stub(:URL, nil) do
      Request.stub(:body, nil) do
        assert_nil TwitterEmbed.render('1234567890123456789', 'http://twitter.com/a/status/1')
      end
    end
  end

  def test_render_returns_markdown_when_fetch_succeeds
    json = '{"text":"hi","user":{"name":"A","screen_name":"a"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, json) do
        md = TwitterEmbed.render('1234567890123456789', 'https://twitter.com/a/status/1', jekyllOpen: '')
        assert_includes md, '> > hi'
        assert_includes md, '@ Twitter Says:'
      end
    end
  end
end

class IframeParserTwitterDispatchTest < Minitest::Test
  def make_iframe_paragraph(iframeSrc)
    TestSupport.paragraph(
      type: 'IFRAME',
      iframe: { 'mediaResource' => { 'iframeSrc' => iframeSrc, 'title' => 'tweet', 'id' => 't1' } }
    )
  end

  def test_renders_twitter_embed_for_direct_twitter_url
    paragraph = make_iframe_paragraph('https://twitter.com/alice/status/1234567890123456789')
    parser = IframeParser.new(false)
    parser.pathPolicy = PathPolicy.new('/abs', 'rel')

    fake = '{"text":"hello","user":{"name":"Alice","screen_name":"alice"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, fake) do
        out = parser.parse(paragraph)
        assert_includes out, '> > hello'
        assert_includes out, '[Alice](https://twitter.com/alice)'
        assert_includes out, '■■■■■■■■■■■■■■'
      end
    end
  end

  def test_renders_twitter_embed_for_embedly_wrapped_twitter_url
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Ftwitter.com%2Falice%2Fstatus%2F1234567890123456789&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    parser = IframeParser.new(false)
    parser.pathPolicy = PathPolicy.new('/abs', 'rel')

    fake = '{"text":"unwrapped ok","user":{"name":"A","screen_name":"a"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, fake) do
        out = parser.parse(paragraph)
        assert_includes out, 'unwrapped ok'
      end
    end
  end

  def test_falls_back_to_plain_link_when_twitter_fetch_fails
    paragraph = make_iframe_paragraph('https://twitter.com/alice/status/1234567890123456789')
    parser = IframeParser.new(false)
    parser.pathPolicy = PathPolicy.new('/abs', 'rel')

    Request.stub(:URL, nil) do
      Request.stub(:body, nil) do
        out = parser.parse(paragraph)
        assert_equal '[tweet](https://twitter.com/alice/status/1234567890123456789)', out
      end
    end
  end

  def test_skips_widgetic_without_hitting_network
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fapp.widgetic.com%2Fcomposition%2Fabc&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    parser = IframeParser.new(false)
    parser.pathPolicy = PathPolicy.new('/abs', 'rel')

    # Any network call would raise NoMethodError on nil because we don't stub
    # Request here. The widgetic short-circuit must run before Request.html.
    assert_nil parser.parse(paragraph)
  end
end
