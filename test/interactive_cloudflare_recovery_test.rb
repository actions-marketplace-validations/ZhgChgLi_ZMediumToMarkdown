require_relative 'test_helper'
require 'stringio'

class InteractiveCloudflareRecoveryTest < Minitest::Test
  Recovery = Request::InteractiveCloudflareRecovery

  # Stand-in for $stdin / $stdout that lets us choose whether tty? returns true.
  class FakeIO < StringIO
    def initialize(string = '', tty: false)
      super(string)
      @tty = tty
    end
    def tty?
      @tty
    end
  end

  # ---------- inCIEnvironment? ----------

  def test_in_ci_environment_when_CI_is_true
    assert Recovery.inCIEnvironment?({ 'CI' => 'true' })
  end

  def test_in_ci_environment_when_GITHUB_ACTIONS_set
    assert Recovery.inCIEnvironment?({ 'GITHUB_ACTIONS' => 'true' })
  end

  def test_not_in_ci_environment_when_no_marker_vars_set
    refute Recovery.inCIEnvironment?({})
  end

  def test_treats_blank_or_false_marker_vars_as_not_ci
    refute Recovery.inCIEnvironment?({ 'CI' => '' })
    refute Recovery.inCIEnvironment?({ 'CI' => 'false' })
    refute Recovery.inCIEnvironment?({ 'CI' => '0' })
  end

  def test_recognizes_common_ci_systems
    %w[GITLAB_CI CIRCLECI JENKINS_URL BUILDKITE TF_BUILD TRAVIS APPVEYOR].each do |key|
      assert Recovery.inCIEnvironment?({ key => 'value' }), "expected #{key} to mark CI"
    end
  end

  # ---------- available? (overall gate) ----------

  def test_unavailable_in_ci_even_with_tty
    refute Recovery.available?(env: { 'CI' => 'true' },
                                stdin: FakeIO.new(tty: true),
                                stdout: FakeIO.new(tty: true))
  end

  def test_unavailable_when_stdin_not_tty
    refute Recovery.available?(env: {},
                                stdin: FakeIO.new(tty: false),
                                stdout: FakeIO.new(tty: true))
  end

  def test_unavailable_when_stdout_not_tty
    refute Recovery.available?(env: {},
                                stdin: FakeIO.new(tty: true),
                                stdout: FakeIO.new(tty: false))
  end

  def test_available_when_tty_and_no_ci_marker
    assert Recovery.available?(env: {},
                                stdin: FakeIO.new(tty: true),
                                stdout: FakeIO.new(tty: true))
  end

  def test_explicit_opt_out_disables_recovery
    refute Recovery.available?(env: { 'MEDIUM_NO_AUTO_BROWSER' => '1' },
                                stdin: FakeIO.new(tty: true),
                                stdout: FakeIO.new(tty: true))
  end

  # ---------- openCommand (cross-platform) ----------

  def test_open_command_on_macos
    assert_equal ['open', 'https://medium.com'],
                 Recovery.openCommand('https://medium.com', hostOS: 'darwin23')
  end

  def test_open_command_on_linux
    assert_equal ['xdg-open', 'https://medium.com'],
                 Recovery.openCommand('https://medium.com', hostOS: 'linux-gnu')
  end

  def test_open_command_on_windows
    assert_equal ['cmd', '/c', 'start', '', 'https://medium.com'],
                 Recovery.openCommand('https://medium.com', hostOS: 'mswin')
  end

  # ---------- run (interactive flow) ----------

  def test_run_prints_guidance_and_returns_true_when_user_presses_enter
    err = StringIO.new
    input = StringIO.new("\n")  # user pressed Enter
    confirmed = Recovery.run('https://medium.com/_/graphql',
                             errput: err, input: input, autoOpen: false)
    assert confirmed
    assert_match(/Cloudflare bot challenge detected/, err.string)
    assert_match(/MEDIUM_NO_AUTO_BROWSER/, err.string)
  end

  def test_run_returns_false_on_eof
    # gets returns nil at EOF (e.g. user hit Ctrl-D).
    confirmed = Recovery.run('https://example.com',
                             errput: StringIO.new, input: StringIO.new, autoOpen: false)
    refute confirmed
  end

  # ---------- once-per-process flag on Request ----------

  def test_resetCloudflareInteractiveResolution_clears_the_flag
    # Just verify the helper exists and runs; behavior is exercised in
    # request_cloudflare_test.rb where we trigger the gate.
    Request.resetCloudflareInteractiveResolution!
    assert true
  end
end
