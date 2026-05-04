require_relative 'test_helper'
require 'tmpdir'
require 'stringio'

class ImageDownloaderTest < Minitest::Test
  def test_returns_true_when_file_already_exists
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      File.write(path, 'cached')
      assert_equal true, ImageDownloader.download(path, 'http://does-not-matter')
      # Existing file content must not be touched.
      assert_equal 'cached', File.read(path)
    end
  end

  def test_writes_downloaded_bytes_to_path
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'subdir', 'a.jpg')
      URI.stub(:open, StringIO.new('image-bytes')) do
        assert_equal true, ImageDownloader.download(path, 'http://example.com/a.jpg')
      end
      assert File.exist?(path)
      assert_equal 'image-bytes', File.read(path)
    end
  end

  def test_returns_false_on_download_error
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      URI.stub(:open, ->(*) { raise 'boom' }) do
        assert_equal false, ImageDownloader.download(path, 'http://broken')
      end
      refute File.exist?(path)
    end
  end
end
