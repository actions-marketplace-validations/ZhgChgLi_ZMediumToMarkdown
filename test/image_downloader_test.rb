require_relative 'test_helper'
require 'tmpdir'
require 'stringio'
require 'net/http'

# A minimal Net::HTTPResponse stand-in. Net::HTTP::Get-based code in
# ImageDownloader only inspects #code, #body, and #[] for the location
# header on redirects.
class FakeHTTPResponse
  attr_reader :code, :body
  def initialize(code:, body: '', headers: {})
    @code = code.to_s
    @body = body
    @headers = headers
  end
  def [](name)
    @headers[name.to_s.downcase]
  end
end

# A stub Net::HTTP that captures the outgoing request so tests can assert
# on headers / URI without hitting the network.
class FakeHTTP
  attr_accessor :captured_request, :captured_uri
  attr_writer :open_timeout, :read_timeout, :use_ssl

  def initialize(host, port, response_for: nil)
    @host = host
    @port = port
    @response_for = response_for # Proc.new { |req, uri| FakeHTTPResponse.new(...) }
  end

  def request(req)
    @captured_request = req
    @captured_uri = URI("https://#{@host}#{req.path}")
    @response_for.call(req, @captured_uri)
  end
end

class ImageDownloaderTest < Minitest::Test
  def setup
    @prev_medium_host = ENV['MEDIUM_HOST']
    @prev_secret      = ENV['MEDIUM_HOST_SECRET']
    @prev_cookies     = $cookies
    ENV.delete('MEDIUM_HOST')
    ENV.delete('MEDIUM_HOST_SECRET')
    $cookies = {}
  end

  def teardown
    @prev_medium_host.nil? ? ENV.delete('MEDIUM_HOST') : ENV['MEDIUM_HOST'] = @prev_medium_host
    @prev_secret.nil?      ? ENV.delete('MEDIUM_HOST_SECRET') : ENV['MEDIUM_HOST_SECRET'] = @prev_secret
    $cookies = @prev_cookies
  end

  def stub_http(response_for:)
    Net::HTTP.stub(:new, ->(host, port) { FakeHTTP.new(host, port, response_for: response_for) }) do
      yield
    end
  end

  def test_returns_true_when_file_already_exists
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      File.write(path, 'cached')
      # No HTTP should happen — file exists.
      assert_equal true, ImageDownloader.download(path, 'http://does-not-matter')
      assert_equal 'cached', File.read(path)
    end
  end

  def test_writes_downloaded_bytes_to_path
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'subdir', 'a.jpg')
      stub_http(response_for: ->(_, _) { FakeHTTPResponse.new(code: 200, body: 'image-bytes') }) do
        assert_equal true, ImageDownloader.download(path, 'https://example.com/a.jpg')
      end
      assert File.exist?(path)
      assert_equal 'image-bytes', File.read(path)
    end
  end

  def test_returns_false_on_non_200
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      stub_http(response_for: ->(_, _) { FakeHTTPResponse.new(code: 404, body: '') }) do
        assert_equal false, ImageDownloader.download(path, 'https://example.com/a.jpg')
      end
      refute File.exist?(path)
    end
  end

  def test_returns_false_when_request_raises
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      stub_http(response_for: ->(_, _) { raise 'boom' }) do
        assert_equal false, ImageDownloader.download(path, 'https://example.com/a.jpg')
      end
      refute File.exist?(path)
    end
  end

  # ---------- proxy rewrite ----------

  def test_rewrites_miro_url_to_worker_origin
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured = nil
      stub_http(response_for: ->(_req, uri) {
        captured = uri
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        assert_equal true, ImageDownloader.download(path, 'https://miro.medium.com/0*abc.jpg')
      end
      assert_equal 'my-worker.example.workers.dev', captured.host
      assert_equal '/0*abc.jpg', captured.path
    end
  end

  def test_rewrites_medium_url_to_worker_origin
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured = nil
      stub_http(response_for: ->(_req, uri) {
        captured = uri
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        assert_equal true, ImageDownloader.download(path, 'https://medium.com/og/foo.png')
      end
      assert_equal 'my-worker.example.workers.dev', captured.host
    end
  end

  def test_third_party_urls_are_not_rewritten
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured = nil
      stub_http(response_for: ->(_req, uri) {
        captured = uri
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        assert_equal true, ImageDownloader.download(path, 'https://i.ytimg.com/vi/abc/hq.jpg')
      end
      assert_equal 'i.ytimg.com', captured.host
    end
  end

  # ---------- proxy auth ----------

  def test_attaches_proxy_secret_when_target_is_proxy
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    ENV['MEDIUM_HOST_SECRET'] = 'top-secret'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured_req = nil
      stub_http(response_for: ->(req, _uri) {
        captured_req = req
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        ImageDownloader.download(path, 'https://miro.medium.com/0*abc.jpg')
      end
      assert_equal 'top-secret', captured_req['X-Medium-Proxy-Secret']
    end
  end

  def test_does_not_send_proxy_secret_to_third_party
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    ENV['MEDIUM_HOST_SECRET'] = 'top-secret'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured_req = nil
      stub_http(response_for: ->(req, _uri) {
        captured_req = req
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        ImageDownloader.download(path, 'https://i.ytimg.com/vi/abc/hq.jpg')
      end
      assert_nil captured_req['X-Medium-Proxy-Secret']
    end
  end

  def test_does_not_send_proxy_secret_when_secret_unset
    ENV['MEDIUM_HOST'] = 'https://my-worker.example.workers.dev/'
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured_req = nil
      stub_http(response_for: ->(req, _uri) {
        captured_req = req
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        ImageDownloader.download(path, 'https://miro.medium.com/0*abc.jpg')
      end
      assert_nil captured_req['X-Medium-Proxy-Secret']
    end
  end

  def test_attaches_cookies_when_present
    $cookies = { 'sid' => 'abc', 'uid' => 'def' }
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      captured_req = nil
      stub_http(response_for: ->(req, _uri) {
        captured_req = req
        FakeHTTPResponse.new(code: 200, body: 'bytes')
      }) do
        ImageDownloader.download(path, 'https://example.com/a.jpg')
      end
      assert_equal 'sid=abc; uid=def', captured_req['Cookie']
    end
  end

  # ---------- redirects ----------

  def test_follows_redirect
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'a.jpg')
      hits = []
      response_for = ->(_req, uri) {
        hits << uri.to_s
        if uri.host == 'example.com'
            FakeHTTPResponse.new(code: 302, body: '', headers: { 'location' => 'https://final.example.com/a.jpg' })
        else
            FakeHTTPResponse.new(code: 200, body: 'bytes')
        end
      }
      stub_http(response_for: response_for) do
        assert_equal true, ImageDownloader.download(path, 'https://example.com/a.jpg')
      end
      assert_equal 2, hits.length
      assert_equal 'bytes', File.read(path)
    end
  end
end
