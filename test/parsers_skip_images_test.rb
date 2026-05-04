require_relative 'test_helper'

# Stub holder so we can detect any unexpected ImageDownloader.download
# invocation from skipImages-mode parsers.
module SkipImagesTestHelpers
  def self.with_no_downloads
    called = false
    ImageDownloader.stub(:download, ->(_a, _b) { called = true; true }) do
      yield
    end
    called
  end
end

class IMGParserSkipImagesTest < Minitest::Test
  def test_emits_remote_url_and_skips_download
    # IMGParser reads paragraph.metadata.id; build one matching that shape.
    p = TestSupport.paragraph(
      type: 'IMG',
      text: 'caption',
      metadata: { 'id' => 'abc.png', '__typename' => 'ImageMetadata' }
    )

    parser = IMGParser.new(false, skipImages: true)
    out = nil
    called = SkipImagesTestHelpers.with_no_downloads { out = parser.parse(p) }

    refute called, 'ImageDownloader.download should not be called when skipImages is true'
    assert_includes out, 'https://miro.medium.com/abc.png'
    assert_includes out, '![caption]'
    refute_includes out, 'assets/' # no local relative path
  end

  def test_default_mode_still_downloads
    # Sanity check: default skipImages: false still tries to download.
    p = TestSupport.paragraph(
      type: 'IMG',
      text: '',
      metadata: { 'id' => 'abc.png', '__typename' => 'ImageMetadata' }
    )
    parser = IMGParser.new(false)
    parser.pathPolicy = PathPolicy.new('/tmp/zmt-test', 'zmt-test')

    called = false
    ImageDownloader.stub(:download, ->(_a, _b) { called = true; false }) do
      parser.parse(p)
    end
    assert called, 'ImageDownloader.download should be called in default mode'
  end

  def test_respects_miro_medium_host_env
    p = TestSupport.paragraph(
      type: 'IMG',
      text: '',
      metadata: { 'id' => 'pic.jpg', '__typename' => 'ImageMetadata' }
    )
    prev = ENV['MIRO_MEDIUM_HOST']
    begin
      ENV['MIRO_MEDIUM_HOST'] = 'https://my-img-proxy.example'
      parser = IMGParser.new(false, skipImages: true)
      out = parser.parse(p)
      assert_includes out, 'https://my-img-proxy.example/pic.jpg'
    ensure
      prev.nil? ? ENV.delete('MIRO_MEDIUM_HOST') : ENV['MIRO_MEDIUM_HOST'] = prev
    end
  end
end

class IframeParserSkipImagesTest < Minitest::Test
  def test_render_thumbnail_link_keeps_remote_url
    p = TestSupport.paragraph(
      type: 'IFRAME',
      iframe: { 'mediaResource' => { 'id' => 'iframe1', 'iframeSrc' => 'https://www.youtube.com/watch?v=abc', 'title' => 'A video' } }
    )

    parser = IframeParser.new(false, skipImages: true)
    called = false
    out = nil
    ImageDownloader.stub(:download, ->(_a, _b) { called = true; true }) do
      out = parser.send(:renderThumbnailLink, p, 'https://www.youtube.com/watch?v=abc',
                        'https://i.ytimg.com/vi/abc/hqdefault.jpg', defaultTitle: 'Youtube')
    end

    refute called
    assert_includes out, 'https://i.ytimg.com/vi/abc/hqdefault.jpg'
    assert_includes out, '[![A video]'
    assert_includes out, '](https://www.youtube.com/watch?v=abc)'
  end
end
