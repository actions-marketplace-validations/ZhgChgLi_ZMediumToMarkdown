require_relative 'test_helper'
require 'tmpdir'

class ZMediumFetcherChainTest < Minitest::Test
  def test_build_parser_chain_order
    fetcher = ZMediumFetcher.new
    head = fetcher.buildParser(PathPolicy.new('/abs', 'rel'))

    types = []
    parser = head
    while parser
      types << parser.class
      parser = parser.respond_to?(:nextParser) ? parser.nextParser : nil
    end

    assert_equal [
      H1Parser, H2Parser, H3Parser, H4Parser,
      PParser, ULIParser, OLIParser,
      MIXTAPEEMBEDParser, PQParser,
      IframeParser, IMGParser,
      BQParser, PREParser, CodeBlockParser, FallbackParser
    ], types
  end
end

class ZMediumFetcherPreprocessTest < Minitest::Test
  def setup
    @fetcher = ZMediumFetcher.new
  end

  def test_oli_index_is_assigned_sequentially
    src = [
      { 'name' => 'a', 'type' => 'OLI', 'text' => 'first' },
      { 'name' => 'b', 'type' => 'OLI', 'text' => 'second' },
      { 'name' => 'c', 'type' => 'OLI', 'text' => 'third' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    indexes = out.select { |p| p.type == 'OLI' }.map(&:oliIndex)
    assert_equal [1, 2, 3], indexes
  end

  def test_oli_index_resets_after_non_oli
    src = [
      { 'name' => 'a', 'type' => 'OLI', 'text' => 'a' },
      { 'name' => 'b', 'type' => 'OLI', 'text' => 'b' },
      { 'name' => 'c', 'type' => 'P',   'text' => 'gap' },
      { 'name' => 'd', 'type' => 'OLI', 'text' => 'd' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    olis = out.select { |p| p.type == 'OLI' }
    assert_equal [1, 2, 1], olis.map(&:oliIndex)
  end

  def test_blank_separator_inserted_between_list_and_text
    src = [
      { 'name' => 'a', 'type' => 'ULI', 'text' => 'item' },
      { 'name' => 'b', 'type' => 'P',   'text' => 'after' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    # ULI, blank, P
    assert_equal 3, out.length
    assert_equal '', out[1].text
    assert_equal 'P', out[1].type
  end

  def test_consecutive_pre_paragraphs_are_merged_into_single_codeblock_when_followed_by_other
    src = [
      { 'name' => 'a', 'type' => 'PRE', 'text' => 'line1' },
      { 'name' => 'b', 'type' => 'PRE', 'text' => 'line2' },
      { 'name' => 'c', 'type' => 'PRE', 'text' => 'line3' },
      { 'name' => 'd', 'type' => 'P',   'text' => 'after' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    # The 3 PREs should collapse into one CODE_BLOCK + the trailing P.
    code_blocks = out.select { |p| p.type == CodeBlockParser.getTypeString }
    assert_equal 1, code_blocks.length
    assert_equal "line1\nline2\nline3", code_blocks.first.text
    refute(out.any? { |p| p.type == 'PRE' })
  end

  def test_consecutive_pre_paragraphs_at_end_of_post_are_merged
    # Regression: previously the merge only triggered when a non-PRE followed,
    # so posts ending in code blocks left dangling PREs.
    src = [
      { 'name' => 'a', 'type' => 'P',   'text' => 'before' },
      { 'name' => 'b', 'type' => 'PRE', 'text' => 'line1' },
      { 'name' => 'c', 'type' => 'PRE', 'text' => 'line2' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    refute(out.any? { |p| p.type == 'PRE' })
    code_blocks = out.select { |p| p.type == CodeBlockParser.getTypeString }
    assert_equal 1, code_blocks.length
    assert_equal "line1\nline2", code_blocks.first.text
  end

  def test_single_trailing_pre_is_left_alone
    src = [
      { 'name' => 'a', 'type' => 'P',   'text' => 'before' },
      { 'name' => 'b', 'type' => 'PRE', 'text' => 'only' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    # A lone PRE shouldn't be converted into a CODE_BLOCK.
    assert_equal 'PRE', out.last.type
  end

  def test_falsy_source_paragraph_is_skipped_not_aborted
    # Regression: original code used `return` here, which terminated the
    # whole post mid-way through preprocessing.
    src = [
      { 'name' => 'a', 'type' => 'P', 'text' => 'first' },
      nil,
      { 'name' => 'b', 'type' => 'P', 'text' => 'second' }
    ]
    out = @fetcher.preprocessParagraphs(src, 'pid')
    texts = out.map(&:text)
    assert_includes texts, 'first'
    assert_includes texts, 'second'
  end
end

class ZMediumFetcherFrontMatterTest < Minitest::Test
  def setup
    @fetcher = ZMediumFetcher.new
  end

  def test_returns_defaults_when_file_does_not_exist
    Dir.mktmpdir do |tmp|
      meta = @fetcher.readExistingFrontMatter(File.join(tmp, 'nope.md'))
      assert_nil meta[:lastModifiedAt]
      assert_equal false, meta[:pin]
      assert_equal false, meta[:lockedPreviewOnly]
    end
  end

  def test_parses_known_fields_from_front_matter
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'post.md')
      File.write(path, <<~MD)
        ---
        title: "x"
        last_modified_at: 2024-01-02T03:04:05Z
        pin: true
        lockedPreviewOnly: true
        ---

        body
      MD
      meta = @fetcher.readExistingFrontMatter(path)
      assert_equal Time.parse('2024-01-02T03:04:05Z').to_i, meta[:lastModifiedAt]
      assert_equal true, meta[:pin]
      assert_equal true, meta[:lockedPreviewOnly]
    end
  end

  def test_ignores_files_without_front_matter
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'post.md')
      File.write(path, "no front matter here\n")
      meta = @fetcher.readExistingFrontMatter(path)
      assert_nil meta[:lastModifiedAt]
    end
  end
end

class ZMediumFetcherShouldSkipTest < Minitest::Test
  PostStub = Struct.new(:latestPublishedAt)

  def setup
    @fetcher = ZMediumFetcher.new
    # Pretend Medium says this post was last touched at t=1000.
    @postInfo = PostStub.new(Time.at(1000))
  end

  def metaWith(lastModifiedAt: 1000, pin: false, lockedPreviewOnly: false)
    { lastModifiedAt: lastModifiedAt, pin: pin, lockedPreviewOnly: lockedPreviewOnly }
  end

  # ---------- happy-path skip ----------

  def test_skips_when_disk_timestamp_matches_and_flags_align_as_false
    assert @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, false, false)
  end

  def test_skips_when_both_flags_are_true_and_match
    meta = metaWith(pin: true, lockedPreviewOnly: true)
    assert @fetcher.shouldSkipExistingPost?(meta, @postInfo, true, true)
  end

  # ---------- the regression: API returns nil, file omits the line ----------

  def test_skips_when_api_returns_nil_isLockedPreviewOnly_and_file_omitted_the_line
    # Helper.createPostInfo only writes `lockedPreviewOnly: true`, so a
    # non-paywalled post on disk will read back as false. Medium's GraphQL
    # may omit the field entirely on re-fetch, giving nil. Both should be
    # treated as "not paywalled" → skip.
    assert @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, false, nil)
  end

  def test_skips_when_isPin_is_nil_and_file_was_not_pinned
    # Single-post mode (`-p`) calls downloadPost with isPin = nil. A post
    # that was never pinned on disk should still skip on re-run.
    assert @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, nil, false)
  end

  def test_skips_when_both_signals_nil_and_file_has_neither_line
    assert @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, nil, nil)
  end

  # ---------- legitimate "must re-download" cases ----------

  def test_does_not_skip_when_file_is_older_than_medium_timestamp
    meta = metaWith(lastModifiedAt: 999)
    refute @fetcher.shouldSkipExistingPost?(meta, @postInfo, false, false)
  end

  def test_does_not_skip_when_lastModifiedAt_is_missing
    meta = metaWith(lastModifiedAt: nil)
    refute @fetcher.shouldSkipExistingPost?(meta, @postInfo, false, false)
  end

  def test_does_not_skip_when_pin_changed_to_true
    refute @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, true, false)
  end

  def test_does_not_skip_when_pin_changed_to_false
    meta = metaWith(pin: true)
    refute @fetcher.shouldSkipExistingPost?(meta, @postInfo, false, false)
  end

  def test_does_not_skip_when_paywall_flipped_on
    refute @fetcher.shouldSkipExistingPost?(metaWith, @postInfo, false, true)
  end

  def test_does_not_skip_when_paywall_flipped_off
    meta = metaWith(lockedPreviewOnly: true)
    refute @fetcher.shouldSkipExistingPost?(meta, @postInfo, false, false)
  end
end

class ZMediumFetcherPathHelperTest < Minitest::Test
  def test_decode_path_preserving_spaces
    assert_equal 'foo%20bar', ZMediumFetcher.decodePathPreservingSpaces('foo+bar')
    assert_equal 'foo%20bar', ZMediumFetcher.decodePathPreservingSpaces('foo bar')
    assert_equal '',          ZMediumFetcher.decodePathPreservingSpaces(nil)
  end
end
