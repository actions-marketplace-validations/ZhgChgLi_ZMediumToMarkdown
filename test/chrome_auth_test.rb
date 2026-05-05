require_relative 'test_helper'
require 'stringio'
require 'ChromeAuth'

class ChromeAuthTest < Minitest::Test
  # Minimal stand-in for Ferrum::Cookies::Cookie — only the three accessors
  # ChromeAuth touches.
  FakeCookie = Struct.new(:name, :value, :domain)

  def fake_browser_with(cookies)
    Object.new.tap do |b|
      b.define_singleton_method(:cookies) { cookies }
    end
  end

  def fake_cookies(list)
    Object.new.tap do |c|
      c.define_singleton_method(:each) do |&block|
        list.each(&block)
      end
    end
  end

  # ---------- mediumDomain? ----------

  def test_medium_domain_accepts_apex_and_subdomain_variants
    assert ChromeAuth.mediumDomain?('medium.com')
    assert ChromeAuth.mediumDomain?('.medium.com')
    assert ChromeAuth.mediumDomain?('cdn.medium.com')
  end

  def test_medium_domain_rejects_unrelated_domains
    refute ChromeAuth.mediumDomain?('example.com')
    refute ChromeAuth.mediumDomain?('mediumish.com')
    refute ChromeAuth.mediumDomain?(nil)
  end

  # ---------- collectMediumCookies ----------

  def test_collect_filters_by_name_and_domain
    cookies = fake_cookies([
      FakeCookie.new('sid',          'sid_val',          '.medium.com'),
      FakeCookie.new('uid',          'uid_val',          'medium.com'),
      FakeCookie.new('cf_clearance', 'cfc_val',          '.medium.com'),
      FakeCookie.new('_cfuvid',      'cfuvid_val',       '.medium.com'),
      FakeCookie.new('sid',          'WRONG_DOMAIN',     'evil.com'),     # filtered out by domain
      FakeCookie.new('other',        'irrelevant',       '.medium.com'),  # filtered out by name
    ])
    result = ChromeAuth.collectMediumCookies(fake_browser_with(cookies))

    assert_equal 'sid_val',    result['sid']
    assert_equal 'uid_val',    result['uid']
    assert_equal 'cfc_val',    result['cf_clearance']
    assert_equal 'cfuvid_val', result['_cfuvid']
    refute_includes result.keys, 'other'
    assert_equal 4, result.size
  end

  def test_collect_returns_empty_when_browser_iteration_raises
    browser = Object.new.tap do |b|
      b.define_singleton_method(:cookies) { raise 'boom' }
    end
    assert_equal({}, ChromeAuth.collectMediumCookies(browser))
  end

  # ---------- available? ----------

  def test_available_returns_false_when_ferrum_load_fails
    ChromeAuth.stub :require, ->(name) { raise LoadError if name == 'ferrum'; true } do
      refute ChromeAuth.available?
    end
  end

  # ---------- promptUser ----------

  def test_prompt_user_writes_guidance_and_reads_one_line
    err = StringIO.new
    input = StringIO.new("\n")
    ChromeAuth.promptUser(err, input, 'https://medium.com/m/signin')
    assert_match(/Sign into Medium/, err.string)
    assert_match(/\.zmediumtomarkdown/, err.string)
    assert_match(/Press Enter when signed in/, err.string)
  end

  # ---------- startSession! / finishSession! / cancelSession! -----

  # Fake browser that records lifecycle calls so we can assert against them.
  class FakeBrowser
    attr_reader :visited, :quitCount

    def initialize(cookies: [], goToError: nil)
      @cookies   = cookies
      @goToError = goToError
      @visited   = []
      @quitCount = 0
    end

    def go_to(url)
      raise @goToError if @goToError
      @visited << url
    end

    def cookies
      list = @cookies
      Object.new.tap do |c|
        c.define_singleton_method(:each) do |&block|
          list.each(&block)
        end
      end
    end

    def quit
      @quitCount += 1
    end
  end

  def setup
    ChromeAuth.cancelSession!  # leak guard between tests
  end

  def teardown
    ChromeAuth.cancelSession!
  end

  def test_start_session_opens_browser_and_navigates
    fake = FakeBrowser.new
    ChromeAuth.stub(:buildBrowser, fake) do
      result = ChromeAuth.startSession!(openURL: 'https://medium.com/m/signin')
      assert_equal({ ok: true, openURL: 'https://medium.com/m/signin' }, result)
    end
    assert ChromeAuth.sessionActive?
    assert_equal ['https://medium.com/m/signin'], fake.visited
  end

  def test_start_session_replaces_existing_session
    first  = FakeBrowser.new
    second = FakeBrowser.new
    sequence = [first, second]
    ChromeAuth.stub(:buildBrowser, ->(*) { sequence.shift }) do
      ChromeAuth.startSession!
      ChromeAuth.startSession!
    end
    assert_equal 1, first.quitCount, 'first browser should be quit when second start kicks in'
    assert ChromeAuth.sessionActive?
  end

  def test_start_session_cleans_up_when_go_to_raises
    fake = FakeBrowser.new(goToError: RuntimeError.new('navigation failed'))
    assert_raises(RuntimeError) do
      ChromeAuth.stub(:buildBrowser, fake) do
        ChromeAuth.startSession!
      end
    end
    refute ChromeAuth.sessionActive?
    assert_equal 1, fake.quitCount
  end

  def test_finish_session_returns_cookies_and_clears_state
    fake = FakeBrowser.new(cookies: [
      FakeCookie.new('sid', 'sid_val', '.medium.com'),
      FakeCookie.new('uid', 'uid_val', 'medium.com'),
    ])
    cookies = nil
    ChromeAuth.stub(:buildBrowser, fake) do
      ChromeAuth.startSession!
      # Avoid touching the real cache file.
      CookieCache.stub(:save, ->(*) {}) do
        CookieCache.stub(:load, {}) do
          cookies = ChromeAuth.finishSession!
        end
      end
    end
    assert_equal({ 'sid' => 'sid_val', 'uid' => 'uid_val' }, cookies)
    refute ChromeAuth.sessionActive?
    assert_equal 1, fake.quitCount
  end

  def test_finish_session_raises_without_active_session
    assert_raises(StandardError) { ChromeAuth.finishSession! }
  end

  def test_cancel_session_is_idempotent
    refute ChromeAuth.cancelSession!
    fake = FakeBrowser.new
    ChromeAuth.stub(:buildBrowser, fake) do
      ChromeAuth.startSession!
    end
    assert ChromeAuth.cancelSession!
    refute ChromeAuth.cancelSession!
    assert_equal 1, fake.quitCount
  end
end
