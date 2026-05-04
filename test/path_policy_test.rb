require_relative 'test_helper'

class PathPolicyTest < Minitest::Test
  def test_relative_path_with_empty_root_path
    policy = PathPolicy.new('/abs', '')
    assert_equal 'foo', policy.getRelativePath('foo')
  end

  def test_relative_path_appends_to_existing
    policy = PathPolicy.new('/abs', 'rel')
    assert_equal 'rel/foo', policy.getRelativePath('foo')
  end

  def test_relative_path_with_nil_last
    policy = PathPolicy.new('/abs', 'rel')
    # The current implementation appends a trailing slash but no last segment.
    assert_equal 'rel/', policy.getRelativePath(nil)
  end

  def test_absolute_path_concatenates
    policy = PathPolicy.new('/abs/root', 'rel')
    assert_equal '/abs/root/foo', policy.getAbsolutePath('foo')
  end

  def test_absolute_path_with_nil_last_returns_root
    policy = PathPolicy.new('/abs/root', 'rel')
    assert_equal '/abs/root', policy.getAbsolutePath(nil)
  end

  def test_absolute_path_with_empty_root
    policy = PathPolicy.new('', 'rel')
    assert_equal 'foo', policy.getAbsolutePath('foo')
  end
end
