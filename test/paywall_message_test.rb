require_relative 'test_helper'

class PaywallMessageTest < Minitest::Test
  def setup
    @prev_cookies = $cookies
    @fetcher = ZMediumFetcher.new
  end

  def teardown
    $cookies = @prev_cookies
  end

  def test_prompts_to_provide_cookies_when_none_present
    $cookies = {}
    msg = @fetcher.paywallMessage
    assert_match(/REQUIRED/, msg)
    assert_match(/sid \/ uid/, msg)
    assert_match(%r{github\.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy}, msg)
  end

  def test_prompts_to_provide_cookies_when_jar_has_blank_values
    $cookies = { 'sid' => '', 'uid' => '' }
    msg = @fetcher.paywallMessage
    assert_match(/REQUIRED/, msg)
  end

  def test_suggests_cookie_validity_when_cookies_were_already_set
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    msg = @fetcher.paywallMessage
    assert_match(/cookies don't grant access/, msg)
    assert_match(/Medium Member account/, msg)
    assert_match(/sliding window|expire/, msg)
  end

  def test_treats_partial_cookies_as_provided
    # If only sid is set, we still consider this an "authenticated" attempt
    # and surface the cookie-validity message rather than the setup prompt.
    $cookies = { 'sid' => 'real_sid' }
    msg = @fetcher.paywallMessage
    assert_match(/cookies don't grant access/, msg)
  end
end
