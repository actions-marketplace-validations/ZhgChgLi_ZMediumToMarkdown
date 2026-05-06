require_relative 'test_helper'

# Coverage for Request.mediumProxiedURL — the rewriter that routes any
# medium.com hit (not just /_/graphql) through MEDIUM_HOST when the user
# has set up a Cloudflare Worker proxy.
class RequestMediumProxyRewriteTest < Minitest::Test
  WORKER = 'https://my-worker.my-account.workers.dev/_/graphql'.freeze
  ORIGIN = 'https://my-worker.my-account.workers.dev'.freeze

  def setup
    @prev = ENV['MEDIUM_HOST']
    ENV.delete('MEDIUM_HOST')
  end

  def teardown
    @prev.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = @prev
  end

  # ---------- no proxy → no rewrite ----------

  def test_returns_input_unchanged_when_medium_host_not_set
    assert_equal 'https://medium.com/p/abc',
                 Request.mediumProxiedURL('https://medium.com/p/abc')
  end

  def test_returns_input_unchanged_when_medium_host_still_default
    ENV['MEDIUM_HOST'] = 'https://medium.com/_/graphql'
    assert_equal 'https://medium.com/p/abc',
                 Request.mediumProxiedURL('https://medium.com/p/abc')
  end

  # ---------- proxy on → rewrite medium.com paths ----------

  def test_rewrites_post_url_to_worker_origin
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal "#{ORIGIN}/zhgchgli/foo-bar-abc123",
                 Request.mediumProxiedURL('https://medium.com/zhgchgli/foo-bar-abc123')
  end

  def test_rewrites_iframe_media_url
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal "#{ORIGIN}/media/abc123",
                 Request.mediumProxiedURL('https://medium.com/media/abc123')
  end

  def test_rewrites_graphql_url_too_no_double_proxy
    # Callers that already hand us ENV['MEDIUM_HOST'] (i.e. the worker URL)
    # short-circuit because the URL doesn't start with https://medium.com.
    # But if some caller happens to pass the literal upstream GraphQL URL,
    # the rewriter routes it through the proxy too — same result.
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal "#{ORIGIN}/_/graphql",
                 Request.mediumProxiedURL('https://medium.com/_/graphql')
  end

  def test_preserves_query_string_and_fragment
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal "#{ORIGIN}/p/abc?source=feed#section",
                 Request.mediumProxiedURL('https://medium.com/p/abc?source=feed#section')
  end

  # ---------- non-medium URLs are pass-through ----------

  def test_does_not_rewrite_non_medium_urls
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal 'https://miro.medium.com/v2/resize:fit:1280/abc',
                 Request.mediumProxiedURL('https://miro.medium.com/v2/resize:fit:1280/abc')
    assert_equal 'https://example.com/page',
                 Request.mediumProxiedURL('https://example.com/page')
  end

  # `mediumish.com` doesn't share a domain root with medium.com — the
  # rewriter's `start_with?('https://medium.com/')` check has the trailing
  # slash precisely to avoid this kind of suffix collision.
  def test_does_not_match_lookalike_domains
    ENV['MEDIUM_HOST'] = WORKER
    assert_equal 'https://medium.com.evil.example/p/abc',
                 Request.mediumProxiedURL('https://medium.com.evil.example/p/abc')
  end

  def test_returns_input_when_url_is_not_a_string
    ENV['MEDIUM_HOST'] = WORKER
    assert_nil Request.mediumProxiedURL(nil)
  end

  # ---------- malformed MEDIUM_HOST ----------

  def test_unparseable_medium_host_falls_back_to_passthrough
    ENV['MEDIUM_HOST'] = 'not a url'
    assert_equal 'https://medium.com/p/abc',
                 Request.mediumProxiedURL('https://medium.com/p/abc')
  end
end
