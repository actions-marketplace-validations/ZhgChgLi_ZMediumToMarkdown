require_relative 'test_helper'
require 'stringio'

class CLIStdoutListParseArgsTest < Minitest::Test
  def setup
    $cookies = {}
    @err = StringIO.new
  end

  def parse(args)
    CLI.parseArgs(args.dup, errput: @err)
  end

  def test_stdout_flag_sets_option
    opts = parse(%w[--stdout -p https://medium.com/p/abc])
    assert_equal true, opts[:stdout]
    assert_equal 'https://medium.com/p/abc', opts[:postURL]
  end

  def test_list_flag_sets_option
    opts = parse(%w[--list -u alice])
    assert_equal true, opts[:list]
    assert_equal 'alice', opts[:username]
  end

  def test_limit_flag_parses_integer
    opts = parse(%w[--list -u alice --limit 5])
    assert_equal 5, opts[:limit]
  end

  def test_limit_without_other_flags_still_parses
    opts = parse(%w[--limit 10])
    assert_equal 10, opts[:limit]
  end

  def test_stdout_without_post_or_user_is_a_no_op
    # No -p / -u means run() returns early via willHitMedium?(options) == false
    opts = parse(%w[--stdout])
    assert_equal true, opts[:stdout]
    assert_nil opts[:postURL]
    assert_nil opts[:username]
  end
end

class CLIStdoutListRunTest < Minitest::Test
  def setup
    $cookies = { 'sid' => 'x', 'uid' => 'y' } # silence setup banner
    @out = StringIO.new
    @err = StringIO.new
  end

  def test_list_without_username_writes_error_to_errput_and_returns
    CLI.run({ list: true }, '/tmp', output: @out, errput: @err)
    assert_match(/--list requires -u\/--username/, @err.string)
    assert_empty @out.string
  end
end
