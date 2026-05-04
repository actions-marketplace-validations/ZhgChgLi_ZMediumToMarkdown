require_relative 'test_helper'
require 'json'

# Net::HTTP#read_body returns ASCII-8BIT, which causes Nokogiri to
# misdetect inline <script> bodies as ISO-8859-1, mojibaking embedded
# CJK/Arabic/Hebrew JSON. These tests cover the UTF-8 force-encoding
# path through Request.html / Request.body, which feed downstream
# Nokogiri parsing (used by IframeParser / Helper.fetchOGImage) and
# the GraphQL JSON pipeline (used by Post.parsePostInfo / Post.fetchPostParagraphs).
class RequestEncodingTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body) do
    def read_body
      body
    end
  end

  def test_html_force_encodes_binary_response_body_to_utf8
    page = '<html><body><meta property="og:title" content="使用 App"></body></html>'
    binary_body = page.dup.force_encoding('ASCII-8BIT')
    response = FakeResponse.new('200', binary_body)

    doc = Request.html(response)
    refute_nil doc

    title = doc.search("meta[property='og:title']").first['content']
    assert_equal '使用 App', title,
                 'CJK content must round-trip without mojibake (would be "ä½¿ç¨ App" if encoding was wrong)'
  end

  def test_body_returns_utf8_string_for_binary_response
    binary = '你好 שלום مرحبا'.dup.force_encoding('ASCII-8BIT')
    response = FakeResponse.new('200', binary)

    out = Request.body(response)
    assert_equal Encoding::UTF_8, out.encoding
    assert_equal '你好 שלום مرحبا', out
    assert out.valid_encoding?
  end

  def test_body_passes_through_already_utf8_strings
    response = FakeResponse.new('200', '使用')
    out = Request.body(response)
    assert_equal Encoding::UTF_8, out.encoding
    assert_equal '使用', out
  end

  def test_html_returns_nil_for_non_2xx_response
    assert_nil Request.html(FakeResponse.new('404', 'not found'))
    assert_nil Request.html(nil)
  end

  def test_body_returns_nil_for_non_2xx_response
    assert_nil Request.body(FakeResponse.new('500', 'oops'))
    assert_nil Request.body(nil)
  end

  def test_body_handles_empty_string_response
    response = FakeResponse.new('200', '')
    assert_equal '', Request.body(response)
  end

  def test_post_info_preserves_cjk_after_forced_utf8_pipeline
    # End-to-end: a binary HTTP body containing the GraphQL JSON
    # response should produce a PostInfo whose title is intact CJK.
    # If Request.readBodyAsUTF8 didn't force UTF-8, JSON.parse would
    # fail on multi-byte content tagged ASCII-8BIT.
    payload = JSON.dump([{
      'data' => {
        'postResult' => {
          'title'          => '使用 App',
          'previewContent' => { 'subtitle' => '中文副標題' },
          'tags'           => []
        }
      }
    }])
    binary_payload = payload.dup.force_encoding('ASCII-8BIT')

    Request.stub(:URL, FakeResponse.new('200', binary_payload)) do
      info = Post.parsePostInfo('abc', PathPolicy.new('/abs', 'rel'))
      assert_equal '使用 App',  info.title
      assert_equal '中文副標題', info.description
    end
  end
end
