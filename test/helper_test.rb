require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'

class HelperTest < Minitest::Test
  def test_escape_markdown_escapes_all_special_chars
    assert_equal '\*\_\`hi\!', Helper.escapeMarkdown('*_`hi!')
  end

  def test_escape_markdown_leaves_plain_text_alone
    assert_equal 'hello world', Helper.escapeMarkdown('hello world')
  end

  def test_escape_html_to_entity
    assert_equal '&lt;b&gt;hi&lt;/b&gt;', Helper.escapeHTML('<b>hi</b>')
  end

  def test_escape_html_to_backslash
    assert_equal '\<b\>hi\</b\>', Helper.escapeHTML('<b>hi</b>', false)
  end

  def test_create_dir_if_not_exist_handles_relative_paths
    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do
        Helper.createDirIfNotExist('a/b/c')
        assert Dir.exist?('a/b/c')
        # Critical: must NOT create a directory at the filesystem root.
        refute Dir.exist?('/a')
      end
    end
  end

  def test_create_dir_if_not_exist_handles_nil
    Helper.createDirIfNotExist(nil)
    Helper.createDirIfNotExist('')
    # No exception means pass.
    assert true
  end

  def test_latest_stable_release_picks_highest_id_non_prerelease
    releases = [
      { 'id' => 5, 'prerelease' => true,  'tag_name' => 'v2.0.0-beta' },
      { 'id' => 4, 'prerelease' => false, 'tag_name' => 'v1.5.0' },
      { 'id' => 3, 'prerelease' => false, 'tag_name' => 'v1.4.0' }
    ]
    assert_equal 'v1.5.0', Helper.latestStableRelease(releases)['tag_name']
  end

  def test_latest_stable_release_returns_nil_if_only_prereleases
    releases = [
      { 'id' => 1, 'prerelease' => true, 'tag_name' => 'v1.0-rc1' }
    ]
    assert_nil Helper.latestStableRelease(releases)
  end

  def test_create_post_info_renders_required_fields
    info = Post::PostInfo.new
    info.title = 'Hello [World]'
    info.creator = 'Z. Hg'
    info.firstPublishedAt = Time.utc(2024, 1, 2, 3, 4, 5)
    info.latestPublishedAt = Time.utc(2024, 1, 3, 3, 4, 5)
    info.collectionName = 'Tech'
    info.tags = ['ruby', 'medium']
    info.description = 'a "quoted" description'
    info.previewImage = 'assets/img.jpg'

    out = Helper.createPostInfo(info, true, false, true)

    assert_includes out, 'title: "Hello World"'
    assert_includes out, 'author: "Z. Hg"'
    assert_includes out, 'date: 2024-01-02T03:04:05'
    assert_includes out, 'last_modified_at: 2024-01-03T03:04:05'
    assert_includes out, 'tags: ["ruby","medium"]'
    assert_includes out, 'image:'
    assert_includes out, '  path: /assets/img.jpg'
    assert_includes out, 'pin: true'
    refute_includes out, 'lockedPreviewOnly:'
    assert_includes out, 'render_with_liquid: false'
    assert out.start_with?("---\n")
    assert out.end_with?("---\n\r\n")
  end

  def test_create_post_info_omits_optional_blocks
    info = Post::PostInfo.new
    info.title = 'T'
    info.creator = 'A'
    info.firstPublishedAt = Time.utc(2024, 1, 2)
    info.latestPublishedAt = Time.utc(2024, 1, 2)
    info.collectionName = nil
    info.tags = nil
    info.description = nil

    out = Helper.createPostInfo(info, false, nil, false)

    refute_includes out, 'image:'
    refute_includes out, 'pin:'
    refute_includes out, 'lockedPreviewOnly:'
    refute_includes out, 'render_with_liquid:'
  end

  def test_create_watermark_includes_url_and_jekyll_target
    text = Helper.createWatermark('https://medium.com/p/abc', true)
    assert_includes text, 'https://medium.com/p/abc'
    assert_includes text, '{:target="_blank"}'
  end

  def test_create_view_full_post_includes_paywall_message
    text = Helper.createViewFullPost('https://medium.com/p/xyz', false)
    assert_includes text, 'paywall'
    assert_includes text, 'https://medium.com/p/xyz'
    refute_includes text, '{:target='
  end
end
