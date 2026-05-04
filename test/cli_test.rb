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
  def setup
    $cookies = {}
    @err = StringIO.new
  end

  def test_warns_when_post_url_set_and_no_cookies
    CLI.warnIfNoCookies({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_match(/Medium login cookie/, @err.string)
    assert_match(/MEDIUM_COOKIE_SID/, @err.string)
  end

  def test_warns_when_username_set_and_no_cookies
    CLI.warnIfNoCookies({ username: 'alice' }, errput: @err)
    assert_match(/Medium login cookie/, @err.string)
  end

  def test_does_not_warn_when_only_sid_present
    $cookies['sid'] = 'x'
    CLI.warnIfNoCookies({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_empty @err.string
  end

  def test_does_not_warn_when_only_uid_present
    $cookies['uid'] = 'x'
    CLI.warnIfNoCookies({ postURL: 'https://medium.com/p/abc' }, errput: @err)
    assert_empty @err.string
  end

  def test_does_not_warn_for_version_only_invocations
    CLI.warnIfNoCookies({ version: true }, errput: @err)
    assert_empty @err.string
  end

  def test_does_not_warn_for_clean_only_invocations
    CLI.warnIfNoCookies({ clean: true }, errput: @err)
    assert_empty @err.string
  end
end
