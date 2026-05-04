require_relative 'test_helper'
require 'json'
require 'stringio'

# End-to-end test that converts a real Medium GraphQL response payload
# through the full pipeline (preprocess + parsers + markup) and compares
# against a golden markdown file.
#
# Run `UPDATE_FIXTURES=1 bundle exec rake test` to regenerate the golden
# file after intentional output changes.
class IntegrationTest < Minitest::Test
  POST_ID         = '7c0974856393'.freeze
  FIXTURE_DIR     = File.expand_path('fixtures', __dir__).freeze
  PAYLOAD_PATH    = File.join(FIXTURE_DIR, "post_#{POST_ID}.json").freeze
  EXPECTED_PATH   = File.join(FIXTURE_DIR, "post_#{POST_ID}.expected.md").freeze

  def test_converts_real_post_into_expected_markdown
    actual = render_post

    if ENV['UPDATE_FIXTURES'] == '1'
      File.write(EXPECTED_PATH, actual)
      skip "Wrote #{EXPECTED_PATH} (re-run without UPDATE_FIXTURES=1 to assert)."
    end

    assert File.file?(EXPECTED_PATH),
           "Missing golden file at #{EXPECTED_PATH}. Run `UPDATE_FIXTURES=1 bundle exec rake test` to create it."
    expected = File.read(EXPECTED_PATH, encoding: 'UTF-8')
    assert_equal expected, actual
  end

  private

  def render_post
    payload = JSON.parse(File.read(PAYLOAD_PATH))
    source_paragraphs = payload.dig('data', 'post', 'viewerEdge', 'fullContent', 'bodyModel', 'paragraphs')

    fetcher = ZMediumFetcher.new
    image_policy = PathPolicy.new('/output', 'assets')
    paragraphs = fetcher.preprocessParagraphs(source_paragraphs, POST_ID)
    start_parser = fetcher.buildParser(image_policy)

    io = StringIO.new
    # Stub all network/filesystem boundaries so the test is hermetic.
    Helper.stub(:fetchOGImage, '') do
      ImageDownloader.stub(:download, true) do
        Request.stub(:URL, nil) do
          Request.stub(:html, nil) do
            Request.stub(:body, nil) do
              paragraphs.each do |p|
                io.puts fetcher.renderParagraph(p, start_parser)
              end
            end
          end
        end
      end
    end
    io.string
  end
end
