require_relative 'test_helper'

# Helpers and shared setup for embedly handler tests.
module IframeParserTestSupport
  def make_iframe_paragraph(iframe_src, title: 'embed', id: 'eid')
    TestSupport.paragraph(
      type: 'IFRAME',
      iframe: { 'mediaResource' => { 'iframeSrc' => iframe_src, 'title' => title, 'id' => id } }
    )
  end

  def parser
    p = IframeParser.new(@isForJekyll || false)
    p.pathPolicy = PathPolicy.new('/abs', 'rel')
    p
  end

  def stub_no_network
    Request.stub(:URL, nil) do
      Request.stub(:html, nil) do
        Request.stub(:body, nil) do
          ImageDownloader.stub(:download, true) do
            Helper.stub(:fetchOGImage, '') do
              yield
            end
          end
        end
      end
    end
  end
end

class IframeXTwitterDispatchTest < Minitest::Test
  include IframeParserTestSupport

  def test_xcom_url_dispatches_through_twitter_embed
    paragraph = make_iframe_paragraph('https://x.com/alice/status/1700000000000000001')
    fake = '{"text":"hello x","user":{"name":"Alice","screen_name":"alice"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, fake) do
        out = parser.parse(paragraph)
        assert_includes out, '> > hello x'
        assert_includes out, '[Alice](https://twitter.com/alice)'
      end
    end
  end

  def test_mobile_twitter_url_dispatches_through_twitter_embed
    paragraph = make_iframe_paragraph('https://mobile.twitter.com/alice/status/1700000000000000002')
    fake = '{"text":"mobile","user":{"name":"Alice","screen_name":"alice"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, fake) do
        out = parser.parse(paragraph)
        assert_includes out, '> > mobile'
      end
    end
  end

  def test_embedly_wrapped_xcom_url_dispatches_through_twitter_embed
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fx.com%2Falice%2Fstatus%2F1700000000000000003&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    fake = '{"text":"unwrapped x","user":{"name":"A","screen_name":"a"},"created_at":"2024-01-15T10:30:00.000Z"}'
    Request.stub(:URL, nil) do
      Request.stub(:body, fake) do
        out = parser.parse(paragraph)
        assert_includes out, 'unwrapped x'
      end
    end
  end
end

class IframeYoutubeVariantsTest < Minitest::Test
  include IframeParserTestSupport

  def test_youtu_be_short_url_extracts_video_id_in_jekyll
    @isForJekyll = true
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ&image=https%3A%2F%2Fimg.youtube.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://www.youtube.com/embed/dQw4w9WgXcQ"'
  end

  def test_youtube_shorts_url_extracts_video_id_in_jekyll
    @isForJekyll = true
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fwww.youtube.com%2Fshorts%2FabcDEF12345&image=https%3A%2F%2Fimg.youtube.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://www.youtube.com/embed/abcDEF12345"'
  end

  def test_classic_watch_url_still_works_in_jekyll
    @isForJekyll = true
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&image=https%3A%2F%2Fimg.youtube.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly)
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://www.youtube.com/embed/dQw4w9WgXcQ"'
  end

  def test_jekyll_falls_back_to_plain_link_when_video_id_unrecoverable
    @isForJekyll = true
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fyoutu.be%2F&image=x&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly, title: 'broken')
    out = parser.parse(paragraph)
    refute_includes out, '<iframe'
    assert_match(/\[broken\]\(https:\/\/youtu\.be\/\)/, out)
  end

  def test_plain_mode_downloads_thumbnail_for_youtu_be_url
    @isForJekyll = false
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ&image=https%3A%2F%2Fimg.youtube.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly, title: 'rickroll')
    ImageDownloader.stub(:download, true) do
      out = parser.parse(paragraph)
      assert_includes out, '![rickroll]'
      assert_includes out, '(https://youtu.be/dQw4w9WgXcQ)'
    end
  end
end

class IframeVimeoEmbedTest < Minitest::Test
  include IframeParserTestSupport

  def test_jekyll_emits_player_iframe_with_video_id
    @isForJekyll = true
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fvimeo.com%2F123456789&image=https%3A%2F%2Fi.vimeocdn.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly, title: 'My Vimeo video')
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://player.vimeo.com/video/123456789"'
    assert_includes out, 'My Vimeo video'
    assert_includes out, 'allowfullscreen'
  end

  def test_plain_mode_downloads_thumbnail_from_embedly_image_param
    @isForJekyll = false
    embedly = 'https://cdn.embedly.com/widgets/media.html?src=foo&url=https%3A%2F%2Fvimeo.com%2F123456789&image=https%3A%2F%2Fi.vimeocdn.com%2Fthumb.jpg&type=text%2Fhtml'
    paragraph = make_iframe_paragraph(embedly, title: 'My Vimeo video')
    ImageDownloader.stub(:download, true) do
      out = parser.parse(paragraph)
      assert_includes out, '![My Vimeo video]'
      assert_includes out, '(https://vimeo.com/123456789)'
    end
  end

  def test_plain_mode_falls_back_to_og_image_when_no_embedly_image
    @isForJekyll = false
    paragraph = make_iframe_paragraph('https://vimeo.com/123456789', title: 'V')
    Helper.stub(:fetchOGImage, 'https://i.vimeocdn.com/og.jpg') do
      ImageDownloader.stub(:download, true) do
        out = parser.parse(paragraph)
        assert_includes out, '![V]'
        assert_includes out, '(https://vimeo.com/123456789)'
      end
    end
  end

  def test_plain_mode_falls_back_to_plain_link_when_no_image_anywhere
    @isForJekyll = false
    paragraph = make_iframe_paragraph('https://vimeo.com/123456789', title: 'V')
    Helper.stub(:fetchOGImage, '') do
      out = parser.parse(paragraph)
      assert_match(/\[V\]\(https:\/\/vimeo\.com\/123456789\)/, out)
      refute_includes out, '![V]'
    end
  end
end

class IframeSoundCloudEmbedTest < Minitest::Test
  include IframeParserTestSupport

  def test_jekyll_emits_soundcloud_player_iframe
    @isForJekyll = true
    paragraph = make_iframe_paragraph('https://soundcloud.com/artist/track-name', title: 'a track')
    out = parser.parse(paragraph)
    assert_includes out, 'w.soundcloud.com/player'
    assert_includes out, 'url=https%3A%2F%2Fsoundcloud.com%2Fartist%2Ftrack-name'
    assert_includes out, 'a track'
  end

  def test_plain_mode_falls_through_to_og_image
    @isForJekyll = false
    paragraph = make_iframe_paragraph('https://soundcloud.com/artist/track-name', title: 'a track')
    Helper.stub(:fetchOGImage, 'https://i1.sndcdn.com/og.jpg') do
      ImageDownloader.stub(:download, true) do
        Request.stub(:URL, nil) do
          # Plain mode goes through parseOgImageEmbed, which doesn't need the
          # html-fetch step (we route off the inner URL before that).
          # We need the html-fetch path though, so stub it to return non-nil.
          fake_html = Nokogiri::HTML('<html><body></body></html>')
          Request.stub(:html, fake_html) do
            out = parser.parse(paragraph)
            assert_includes out, '![a track]'
            assert_includes out, '(https://soundcloud.com/artist/track-name)'
          end
        end
      end
    end
  end
end

class IframeSpotifyEmbedTest < Minitest::Test
  include IframeParserTestSupport

  def test_jekyll_emits_track_embed_iframe
    @isForJekyll = true
    paragraph = make_iframe_paragraph('https://open.spotify.com/track/3n3Ppam7vgaVa1iaRUc9Lp', title: 'a song')
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://open.spotify.com/embed/track/3n3Ppam7vgaVa1iaRUc9Lp"'
    assert_includes out, 'a song'
  end

  def test_jekyll_emits_album_embed_iframe
    @isForJekyll = true
    paragraph = make_iframe_paragraph('https://open.spotify.com/album/1A2GTWGtFfWp7KSQTwWOyo')
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://open.spotify.com/embed/album/1A2GTWGtFfWp7KSQTwWOyo"'
  end

  def test_jekyll_emits_episode_embed_iframe
    @isForJekyll = true
    paragraph = make_iframe_paragraph('https://open.spotify.com/episode/4xUZb4l9qjUE0HwGGVwAYj')
    out = parser.parse(paragraph)
    assert_includes out, 'src="https://open.spotify.com/embed/episode/4xUZb4l9qjUE0HwGGVwAYj"'
  end
end

class IframeRegistryDispatchTest < Minitest::Test
  include IframeParserTestSupport

  def test_widgetic_still_short_circuits_without_network
    paragraph = make_iframe_paragraph('https://app.widgetic.com/composition/abc')
    # No Request stub -> any network call would NoMethodError.
    assert_nil parser.parse(paragraph)
  end

  def test_unknown_host_falls_through_to_og_image_path
    @isForJekyll = false
    paragraph = make_iframe_paragraph('https://example.com/some-cool-thing', title: 'cool')
    fake_html = Nokogiri::HTML('<html><body></body></html>')
    Request.stub(:URL, nil) do
      Request.stub(:html, fake_html) do
        Helper.stub(:fetchOGImage, 'https://example.com/og.jpg') do
          out = parser.parse(paragraph)
          assert_includes out, '![cool]'
          assert_includes out, '(https://example.com/some-cool-thing)'
        end
      end
    end
  end
end
