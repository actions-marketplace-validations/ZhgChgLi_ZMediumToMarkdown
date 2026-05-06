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

class RequestProxyURIDetectionTest < Minitest::Test
  WORKER_GRAPHQL = 'https://my-worker.my-account.workers.dev/_/graphql'.freeze

  def setup
    @prev_medium = ENV['MEDIUM_HOST']
    ENV.delete('MEDIUM_HOST')
  end

  def teardown
    @prev_medium.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = @prev_medium
  end

  def test_returns_false_when_no_proxy_configured
    refute Request.proxyURI?(URI('https://medium.com/p/abc'))
    refute Request.proxyURI?(URI('https://my-worker.my-account.workers.dev/abc'))
  end

  def test_returns_true_when_uri_matches_medium_proxy_host
    ENV['MEDIUM_HOST'] = WORKER_GRAPHQL
    assert Request.proxyURI?(URI('https://my-worker.my-account.workers.dev/_/graphql'))
    assert Request.proxyURI?(URI('https://my-worker.my-account.workers.dev/p/abc'))
    # Miro hits derive their host from MEDIUM_HOST origin too, so they
    # match the same proxy host and pass the gate.
    assert Request.proxyURI?(URI('https://my-worker.my-account.workers.dev/0*abc.png'))
  end

  def test_returns_false_for_upstream_medium_when_proxy_set
    # Even with proxy configured, a literal medium.com URI is not "going
    # to the proxy" — the rewriter would have changed it before we reach
    # this check, but the guard still has to refuse it so SECRET never
    # heads to upstream Medium.
    ENV['MEDIUM_HOST'] = WORKER_GRAPHQL
    refute Request.proxyURI?(URI('https://medium.com/p/abc'))
    refute Request.proxyURI?(URI('https://miro.medium.com/v2/abc.png'))
  end

  def test_returns_false_when_env_still_points_to_upstream_default
    ENV['MEDIUM_HOST'] = 'https://medium.com/_/graphql'
    refute Request.proxyURI?(URI('https://medium.com/p/abc'))
  end

  def test_returns_false_for_unrelated_third_party_host
    ENV['MEDIUM_HOST'] = WORKER_GRAPHQL
    refute Request.proxyURI?(URI('https://twitter.com/i/api/graphql/foo'))
  end

  def test_handles_nil_uri_and_uri_without_host
    refute Request.proxyURI?(nil)
    refute Request.proxyURI?(URI('mailto:nobody@example.com'))
  end

  def test_does_not_blow_up_on_unparseable_env
    ENV['MEDIUM_HOST'] = 'not a url'
    refute Request.proxyURI?(URI('https://my-worker.my-account.workers.dev/p/abc'))
  end
end

class RequestMiroHostTest < Minitest::Test
  WORKER_GRAPHQL = 'https://my-worker.my-account.workers.dev/_/graphql'.freeze

  def setup
    @prev_medium = ENV['MEDIUM_HOST']
    ENV.delete('MEDIUM_HOST')
  end

  def teardown
    @prev_medium.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = @prev_medium
  end

  def test_returns_upstream_when_medium_host_unset
    assert_equal 'https://miro.medium.com', Request.miroHost
  end

  def test_falls_back_to_medium_host_origin_when_proxy_set
    ENV['MEDIUM_HOST'] = WORKER_GRAPHQL
    assert_equal 'https://my-worker.my-account.workers.dev', Request.miroHost
  end

  def test_falls_back_to_upstream_when_medium_host_is_default
    ENV['MEDIUM_HOST'] = 'https://medium.com/_/graphql'
    assert_equal 'https://miro.medium.com', Request.miroHost
  end
end
