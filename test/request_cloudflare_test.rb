require_relative 'test_helper'

class RequestCloudflareDetectionTest < Minitest::Test
  FakeResponse = Struct.new(:code, :headers, :body) do
    def [](name)
      headers[name]
    end
  end

  def make(code, header_value: nil, body: '')
    FakeResponse.new(code.to_s, { 'cf-mitigated' => header_value }, body)
  end

  def test_403_with_cf_mitigated_challenge_is_detected
    assert Request.cloudflareBlocked?(make(403, header_value: 'challenge'))
  end

  def test_403_with_cf_mitigated_block_is_detected
    assert Request.cloudflareBlocked?(make(403, header_value: 'block'))
  end

  def test_503_with_managed_challenge_header_is_detected
    assert Request.cloudflareBlocked?(make(503, header_value: 'managed_challenge'))
  end

  def test_403_with_just_a_moment_body_is_detected
    body = '<html><body><h1>Just a moment...</h1><div id="cf-error-details"></div></body></html>'
    assert Request.cloudflareBlocked?(make(403, body: body))
  end

  def test_503_with_attention_required_body_is_detected
    body = '<html><body><h1>Attention Required! | Cloudflare</h1></body></html>'
    assert Request.cloudflareBlocked?(make(503, body: body))
  end

  def test_403_with_unrelated_body_is_not_treated_as_cloudflare
    assert_equal false, Request.cloudflareBlocked?(make(403, body: '<h1>Forbidden by app</h1>'))
  end

  def test_200_with_just_a_moment_body_is_not_a_block
    # We deliberately only check Cloudflare on error codes; a 200 page
    # that happens to contain the phrase shouldn't be treated as blocked.
    assert_equal false, Request.cloudflareBlocked?(make(200, body: 'Just a moment...'))
  end

  def test_404_is_not_cloudflare
    assert_equal false, Request.cloudflareBlocked?(make(404))
  end

  def test_nil_response_returns_false
    assert_equal false, Request.cloudflareBlocked?(nil)
  end

  def test_error_message_carries_cookie_setup_guidance
    err = Request::CloudflareBlockedError.new(403, 'https://medium.com/_/graphql')
    msg = err.message
    assert_match(/HTTP 403/, msg)
    assert_match(/https:\/\/medium.com\/_\/graphql/, msg)
    # Tiered guidance covers both local-machine and CI / Worker-proxy paths.
    assert_match(/Local machine/, msg)
    assert_match(/CI \/ CD/, msg)
    assert_match(/Cloudflare Worker proxy/, msg)
    assert_match(/MEDIUM_COOKIE_SID/, msg)
    assert_match(/MEDIUM_HOST/, msg)
    # Wiki URL is the canonical setup guide.
    assert_match(%r{github\.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy}, msg)
  end
end
