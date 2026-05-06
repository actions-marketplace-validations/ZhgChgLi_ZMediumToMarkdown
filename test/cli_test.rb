require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'CookieCache'
require 'ChromeAuth'

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

  def test_non_interactive_flag_sets_option_and_env
    prev = ENV['MEDIUM_NO_AUTO_BROWSER']
    begin
      ENV.delete('MEDIUM_NO_AUTO_BROWSER')
      opts = parse(%w[--non-interactive])
      assert_equal true, opts[:nonInteractive]
      assert_equal '1', ENV['MEDIUM_NO_AUTO_BROWSER']
    ensure
      prev.nil? ? ENV.delete('MEDIUM_NO_AUTO_BROWSER') : ENV['MEDIUM_NO_AUTO_BROWSER'] = prev
    end
  end

  def test_cf_clearance_and_cfuvid_flags_populate_cookie_jar
    parse(['--cookie_cf_clearance', 'cfc', '--cookie_cfuvid', 'cfu'])
    assert_equal 'cfc', $cookies['cf_clearance']
    assert_equal 'cfu', $cookies['_cfuvid']
  end

  def test_auth_flag_sets_option
    opts = parse(%w[--auth])
    assert_equal true, opts[:auth]
  end
end

class CLIRunAuthTest < Minitest::Test
  def setup
    $cookies = {}
    @err = StringIO.new
  end

  def test_warns_and_returns_when_chrome_unavailable
    ChromeAuth.stub(:available?, false) do
      CLI.runAuth(errput: @err)
    end
    assert_match(/Chrome was not detected/, @err.string)
    assert_includes @err.string, CLI::COOKIE_SETUP_URL
  end

  def test_invokes_login_writes_cookies_into_jar_and_prints_summary
    fake_login = ->(**_) { { 'sid' => 'a', 'uid' => 'b', 'cf_clearance' => 'c', '_cfuvid' => 'd' } }
    ChromeAuth.stub(:available?, true) do
      ChromeAuth.stub(:login!, fake_login) do
        CLI.runAuth(errput: @err)
      end
    end
    assert_equal 'a', $cookies['sid']
    assert_equal 'b', $cookies['uid']
    assert_match(/Captured sid \/ uid \/ cf_clearance \/ _cfuvid/, @err.string)
    assert_includes @err.string, CookieCache.path
  end

  def test_warns_when_no_cookies_captured
    ChromeAuth.stub(:available?, true) do
      ChromeAuth.stub(:login!, ->(**_) { {} }) do
        CLI.runAuth(errput: @err)
      end
    end
    assert_match(/No cookies were captured/, @err.string)
  end

  def test_swallows_login_errors
    boom = ->(**_) { raise 'browser exploded' }
    ChromeAuth.stub(:available?, true) do
      ChromeAuth.stub(:login!, boom) do
        CLI.runAuth(errput: @err)
      end
    end
    assert_match(/Auto-login failed/, @err.string)
  end
end

class CLILoadCookiesTest < Minitest::Test
  ENV_KEYS = %w[MEDIUM_COOKIE_SID MEDIUM_COOKIE_UID MEDIUM_COOKIE_CF_CLEARANCE MEDIUM_COOKIE_CFUVID ZMEDIUM_COOKIE_CACHE_PATH].freeze

  def setup
    $cookies = {}
    @prev_env = ENV_KEYS.to_h { |k| [k, ENV[k]] }
    ENV_KEYS.each { |k| ENV.delete(k) }
    @tmp = Dir.mktmpdir('zmedium-cli-cache-')
    ENV['ZMEDIUM_COOKIE_CACHE_PATH'] = File.join(@tmp, 'cache.bin')
  end

  def teardown
    @prev_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    FileUtils.remove_entry(@tmp) if File.exist?(@tmp)
  end

  def test_cache_fills_missing_cookies_when_env_and_flags_absent
    CookieCache.save({ 'sid' => 'cache_sid', 'uid' => 'cache_uid' })
    CLI.loadCookies!
    assert_equal 'cache_sid', $cookies['sid']
    assert_equal 'cache_uid', $cookies['uid']
  end

  def test_env_takes_precedence_over_cache
    CookieCache.save({ 'sid' => 'cache_sid' })
    ENV['MEDIUM_COOKIE_SID'] = 'env_sid'
    CLI.loadCookies!
    assert_equal 'env_sid', $cookies['sid']
  end

  def test_cli_flag_takes_precedence_over_env_and_cache
    CookieCache.save({ 'sid' => 'cache_sid' })
    ENV['MEDIUM_COOKIE_SID'] = 'env_sid'
    $cookies['sid'] = 'flag_sid'   # simulate flag-set
    CLI.loadCookies!
    assert_equal 'flag_sid', $cookies['sid']
  end

  def test_cache_provides_cf_clearance_and_cfuvid
    CookieCache.save({ 'cf_clearance' => 'cfc', '_cfuvid' => 'cfu' })
    CLI.loadCookies!
    assert_equal 'cfc', $cookies['cf_clearance']
    assert_equal 'cfu', $cookies['_cfuvid']
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
    # One-line warning that names what's missing and links the wiki.
    assert_match(/Medium cookies/, @err.string)
    assert_match(/MEDIUM_HOST/,    @err.string)
    assert_match(/MIRO_MEDIUM_HOST/, @err.string)
    assert_includes @err.string, CLI::COOKIE_SETUP_URL
  end

  def test_banner_is_a_single_line
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    body = @err.string.strip
    refute_empty body
    # Exactly one line of warning, plus the trailing newline from puts.
    assert_equal 1, body.lines.size, "expected one-line banner, got:\n#{body}"
  end

  def test_warns_when_username_set_and_no_cookies
    CLI.warnAboutMissingSetup({ username: 'alice' }, errput: @err)
    assert_match(/Medium cookies/, @err.string)
  end

  def test_warns_about_proxies_only_when_cookies_present
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    refute_match(/Medium cookies/, @err.string)
    assert_match(/MEDIUM_HOST/,      @err.string)
    assert_match(/MIRO_MEDIUM_HOST/, @err.string)
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
    assert_match(/MEDIUM_HOST/, @err.string)
  end

  def test_treats_default_miro_host_as_unconfigured
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST']      = GRAPHQL_PROXY
    ENV['MIRO_MEDIUM_HOST'] = 'https://miro.medium.com'
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/MIRO_MEDIUM_HOST/, @err.string)
  end

  def test_warns_only_about_image_proxy_when_cookies_and_graphql_proxy_set
    $cookies = { 'sid' => 'real_sid', 'uid' => 'real_uid' }
    ENV['MEDIUM_HOST'] = GRAPHQL_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    refute_match(/Medium cookies/,    @err.string)
    refute_includes @err.string, '(MEDIUM_HOST)'
    assert_includes @err.string, '(MIRO_MEDIUM_HOST)'
  end

  def test_warns_only_about_cookies_when_both_proxies_set
    ENV['MEDIUM_HOST']      = GRAPHQL_PROXY
    ENV['MIRO_MEDIUM_HOST'] = IMAGE_PROXY
    CLI.warnAboutMissingSetup({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/Medium cookies/, @err.string)
    refute_includes @err.string, '(MEDIUM_HOST)'
    refute_includes @err.string, '(MIRO_MEDIUM_HOST)'
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
