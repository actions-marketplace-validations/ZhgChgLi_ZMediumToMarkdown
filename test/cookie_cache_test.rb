require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'CookieCache'

class CookieCacheTest < Minitest::Test
  PATH_ENV = CookieCache::PATH_ENV

  def setup
    @prev = ENV[PATH_ENV]
    @tmp = Dir.mktmpdir('zmedium-cache-test-')
    ENV[PATH_ENV] = File.join(@tmp, 'zmedium_cookies.bin')
  end

  def teardown
    @prev.nil? ? ENV.delete(PATH_ENV) : ENV[PATH_ENV] = @prev
    FileUtils.remove_entry(@tmp) if File.exist?(@tmp)
  end

  def test_path_uses_env_override_when_set
    assert_equal File.join(@tmp, 'zmedium_cookies.bin'), CookieCache.path
  end

  def test_path_falls_back_to_home_dotfile_when_env_unset
    ENV.delete(PATH_ENV)
    assert_equal File.join(Dir.home, '.zmediumtomarkdown'), CookieCache.path
  end

  def test_load_returns_empty_when_file_missing
    assert_equal({}, CookieCache.load)
  end

  def test_save_and_load_roundtrip
    CookieCache.save({ 'sid' => 'a', 'uid' => 'b', 'cf_clearance' => 'c' })
    assert_equal({ 'sid' => 'a', 'uid' => 'b', 'cf_clearance' => 'c' }, CookieCache.load)
  end

  def test_save_writes_with_0600_permissions
    CookieCache.save({ 'sid' => 'a' })
    mode = File.stat(CookieCache.path).mode & 0o777
    assert_equal 0o600, mode
  end

  def test_file_is_encrypted_not_plaintext_json
    CookieCache.save({ 'sid' => 'super_secret_value' })
    blob = File.binread(CookieCache.path)
    refute_includes blob, 'super_secret_value', 'cache file should not contain plaintext cookie value'
    refute_includes blob, 'sid', 'cache file should not contain plaintext key name'
  end

  def test_each_save_uses_a_fresh_iv
    CookieCache.save({ 'sid' => 'same_value' })
    blob1 = File.binread(CookieCache.path)
    CookieCache.save({ 'sid' => 'same_value' })
    blob2 = File.binread(CookieCache.path)
    refute_equal blob1, blob2, 'identical plaintext should produce different ciphertext (random IV)'
  end

  def test_load_swallows_corrupt_blob
    FileUtils.mkdir_p(File.dirname(CookieCache.path))
    File.binwrite(CookieCache.path, 'not a valid encrypted blob')
    assert_equal({}, CookieCache.load)
  end

  def test_load_swallows_tampered_ciphertext
    CookieCache.save({ 'sid' => 'a' })
    blob = File.binread(CookieCache.path)
    # Flip a byte inside the ciphertext region (after IV + tag).
    tampered = blob.dup.force_encoding(Encoding::ASCII_8BIT)
    tampered.setbyte(CookieCache::IV_LEN + CookieCache::TAG_LEN,
                     (tampered.getbyte(CookieCache::IV_LEN + CookieCache::TAG_LEN) ^ 0xFF))
    File.binwrite(CookieCache.path, tampered)
    # GCM tag verification fails → cipher.final raises → we return {}.
    assert_equal({}, CookieCache.load)
  end

  def test_save_skips_empty_hash
    CookieCache.save({})
    refute File.exist?(CookieCache.path), 'should not create file for empty cache'
  end

  def test_clear_removes_file
    CookieCache.save({ 'sid' => 'a' })
    assert File.exist?(CookieCache.path)
    CookieCache.clear
    refute File.exist?(CookieCache.path)
  end

  def test_clear_is_noop_when_missing
    CookieCache.clear  # should not raise
    assert true
  end
end
