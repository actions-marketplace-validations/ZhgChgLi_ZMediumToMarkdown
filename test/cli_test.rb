require_relative 'test_helper'
require 'stringio'

class CLIParseArgsTest < Minitest::Test
  def setup
    $cookies = {}
    @err = StringIO.new
  end

  def parse(args)
    CLI.parseArgs(args.dup, errput: @err)
  end

  def test_username_flag_sets_username
    opts = parse(%w[-u alice])
    assert_equal 'alice', opts[:username]
    refute opts[:jekyll]
  end

  def test_post_url_flag_sets_post_url
    opts = parse(%w[-p https://medium.com/p/abc])
    assert_equal 'https://medium.com/p/abc', opts[:postURL]
    refute opts[:jekyll]
  end

  def test_jekyll_modifier_with_username_does_not_warn
    opts = parse(%w[-u alice --jekyll])
    assert_equal 'alice', opts[:username]
    assert_equal true, opts[:jekyll]
    assert_empty @err.string
  end

  def test_jekyll_modifier_with_post_url
    opts = parse(['-p', 'https://medium.com/p/abc', '--jekyll'])
    assert_equal 'https://medium.com/p/abc', opts[:postURL]
    assert_equal true, opts[:jekyll]
  end

  def test_deprecated_jekyll_username_still_works_and_warns
    opts = parse(%w[-j alice])
    assert_equal 'alice', opts[:username]
    assert_equal true, opts[:jekyll]
    assert_match(/deprecated/, @err.string)
    assert_match(/--jekyll -u USERNAME/, @err.string)
  end

  def test_deprecated_jekyll_post_url_still_works_and_warns
    opts = parse(['-k', 'https://medium.com/p/abc'])
    assert_equal 'https://medium.com/p/abc', opts[:postURL]
    assert_equal true, opts[:jekyll]
    assert_match(/deprecated/, @err.string)
    assert_match(/--jekyll -p POST_URL/, @err.string)
  end

  def test_cookie_flags_populate_cookie_jar
    parse(%w[-s sid_value -d uid_value])
    assert_equal 'sid_value', $cookies['sid']
    assert_equal 'uid_value', $cookies['uid']
  end

  def test_medium_host_flag_sets_env
    prev = ENV['MEDIUM_HOST']
    begin
      ENV.delete('MEDIUM_HOST')
      parse(['-x', 'https://my-worker.example.workers.dev/_/graphql'])
      assert_equal 'https://my-worker.example.workers.dev/_/graphql', ENV['MEDIUM_HOST']
    ensure
      prev.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = prev
    end
  end

  def test_medium_host_long_flag_sets_env
    prev = ENV['MEDIUM_HOST']
    begin
      ENV.delete('MEDIUM_HOST')
      parse(['--medium_host', 'https://proxy.example/_/graphql'])
      assert_equal 'https://proxy.example/_/graphql', ENV['MEDIUM_HOST']
    ensure
      prev.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = prev
    end
  end

  def test_miro_medium_host_flag_sets_env
    prev = ENV['MIRO_MEDIUM_HOST']
    begin
      ENV.delete('MIRO_MEDIUM_HOST')
      parse(['--miro_medium_host', 'https://image-proxy.example'])
      assert_equal 'https://image-proxy.example', ENV['MIRO_MEDIUM_HOST']
    ensure
      prev.nil? ? ENV.delete('MIRO_MEDIUM_HOST') : ENV['MIRO_MEDIUM_HOST'] = prev
    end
  end

  def test_help_flag_returns_options_with_help_text
    opts = parse(%w[-h])
    refute_nil opts[:help]
    assert_includes opts[:help], '-s, --cookie_sid'
    assert_includes opts[:help], '--jekyll'
  end

  def test_version_flag
    opts = parse(%w[-v])
    assert_equal true, opts[:version]
  end

  def test_clean_flag
    opts = parse(%w[-c])
    assert_equal true, opts[:clean]
  end

  def test_upgrade_flag
    opts = parse(%w[-n])
    assert_equal true, opts[:upgrade]
  end
end

class CLICookieEnvTest < Minitest::Test
  def setup
    $cookies = {}
    @prev_sid = ENV['MEDIUM_COOKIE_SID']
    @prev_uid = ENV['MEDIUM_COOKIE_UID']
    ENV.delete('MEDIUM_COOKIE_SID')
    ENV.delete('MEDIUM_COOKIE_UID')
  end

  def teardown
    ENV['MEDIUM_COOKIE_SID'] = @prev_sid
    ENV['MEDIUM_COOKIE_UID'] = @prev_uid
  end

  def test_loads_sid_and_uid_from_env_when_unset
    ENV['MEDIUM_COOKIE_SID'] = 'env_sid'
    ENV['MEDIUM_COOKIE_UID'] = 'env_uid'
    CLI.loadCookiesFromEnv!
    assert_equal 'env_sid', $cookies['sid']
    assert_equal 'env_uid', $cookies['uid']
  end

  def test_cli_flags_take_precedence_over_env
    ENV['MEDIUM_COOKIE_SID'] = 'env_sid'
    $cookies['sid'] = 'cli_sid'
    CLI.loadCookiesFromEnv!
    assert_equal 'cli_sid', $cookies['sid']
  end

  def test_empty_env_value_is_ignored
    ENV['MEDIUM_COOKIE_SID'] = ''
    CLI.loadCookiesFromEnv!
    assert CLI.cookieMissing?('sid')
  end
end

class CLIWarningTest < Minitest::Test
  GRAPHQL_PROXY = 'https://my-worker.example.workers.dev/_/graphql'.freeze
  IMAGE_PROXY   = 'https://my-image-worker.example.workers.dev'.freeze

  def setup
    $cookies = {}
    @err = StringIO.new
    @prev_medium_host = ENV['MEDIUM_HOST']
    @prev_miro_host   = ENV['MIRO_MEDIUM_HOST']
    # Default = nothing configured; individual tests opt into "configured"
    # by setting these env vars themselves.
    ENV.delete('MEDIUM_HOST')
    ENV.delete('MIRO_MEDIUM_HOST')
  end

  def teardown
    @prev_medium_host.nil? ? ENV.delete('MEDIUM_HOST')      : ENV['MEDIUM_HOST']      = @prev_medium_host
    @prev_miro_host.nil?   ? ENV.delete('MIRO_MEDIUM_HOST') : ENV['MIRO_MEDIUM_HOST'] = @prev_miro_host
  end

  def test_warns_when_post_url_set_and_no_cookies
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    # Banner lists what's missing and the empirical limits + setup guidance.
    assert_match(/Medium login cookies/, @err.string)
    assert_match(/Cloudflare Worker proxy for Medium GraphQL/, @err.string)
    assert_match(/Cloudflare Worker proxy for image CDN/, @err.string)
    assert_match(/MEDIUM_COOKIE_SID/, @err.string)
    assert_match(/MEDIUM_HOST/, @err.string)
    assert_match(/MIRO_MEDIUM_HOST/, @err.string)
  end

  def test_warns_when_username_set_and_no_cookies
    CLI.warnAboutMissingSetup({ username: 'alice' }, errput: @err)
    assert_match(/Medium login cookies/, @err.string)
  end

  def test_warns_about_proxies_only_when_cookies_present
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    refute_includes @err.string, 'Medium login cookies (sid / uid).'
    assert_match(/Cloudflare Worker proxy for Medium GraphQL/, @err.string)
    assert_match(/Cloudflare Worker proxy for image CDN/, @err.string)
  end

  def test_does_not_warn_when_everything_configured
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST']      = GRAPHQL_PROXY
    ENV['MIRO_MEDIUM_HOST'] = IMAGE_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_empty @err.string
  end

  def test_treats_default_medium_host_as_unconfigured
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST']      = 'https://medium.com/_/graphql'
    ENV['MIRO_MEDIUM_HOST'] = IMAGE_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/Cloudflare Worker proxy for Medium GraphQL/, @err.string)
  end

  def test_treats_default_miro_host_as_unconfigured
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST']      = GRAPHQL_PROXY
    ENV['MIRO_MEDIUM_HOST'] = 'https://miro.medium.com'
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/Cloudflare Worker proxy for image CDN/, @err.string)
  end

  def test_warns_only_about_image_proxy_when_cookies_and_graphql_proxy_set
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST'] = GRAPHQL_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    refute_includes @err.string, 'Medium login cookies (sid / uid).'
    refute_includes @err.string, 'Cloudflare Worker proxy for Medium GraphQL'
    assert_match(/Cloudflare Worker proxy for image CDN/, @err.string)
  end

  def test_warns_only_about_cookies_when_both_proxies_set
    ENV['MEDIUM_HOST']      = GRAPHQL_PROXY
    ENV['MIRO_MEDIUM_HOST'] = IMAGE_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/Medium login cookies \(sid \/ uid\)\./, @err.string)
    refute_includes @err.string, 'Cloudflare Worker proxy for Medium GraphQL'
    refute_includes @err.string, 'Cloudflare Worker proxy for image CDN'
  end

  def test_does_not_warn_for_version_only_invocations
    CLI.warnAboutMissingSetup({ version: true }, errput: @err)
    assert_empty @err.string
  end

  def test_does_not_warn_for_clean_only_invocations
    CLI.warnAboutMissingSetup({ clean: true }, errput: @err)
    assert_empty @err.string
  end
end
