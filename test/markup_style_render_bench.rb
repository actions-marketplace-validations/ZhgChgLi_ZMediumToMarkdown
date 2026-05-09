require_relative 'test_helper'
require 'benchmark'

# Standalone micro-benchmark: not part of `rake test`. Run with:
#   bundle exec ruby -Ilib -Itest test/markup_style_render_bench.rb
#
# Builds N synthetic paragraphs each with text length L and m markups,
# measures total render time, and reports per-paragraph mean. The shape
# (large m, modest L) is designed to expose the O(L * m) hot path that
# previously lived in `walkCharsWithTags`'s `tags.select { |t| ... }` scan.
class MarkupStyleRenderBench
  N = (ENV['BENCH_N'] || 1000).to_i
  L = (ENV['BENCH_L'] || 200).to_i
  M = (ENV['BENCH_M'] || 10).to_i

  def self.build_paragraph(seed)
    rng = Random.new(seed)
    text = (0...L).map { (rng.rand(26) + 97).chr }.join
    markups = (0...M).map do
      a = rng.rand(L)
      b = rng.rand(L)
      a, b = b, a if a > b
      { 'type' => %w[STRONG EM CODE].sample(random: rng), 'start' => a, 'end' => b + 1 }
    end
    TestSupport.paragraph(text: text, markups: markups)
  end

  def self.run
    paragraphs = (0...N).map { |i| build_paragraph(i) }
    # Warm-up to amortise YJIT / cache effects.
    paragraphs.first(50).each { |p| MarkupStyleRender.new(p, false).parse }

    elapsed = Benchmark.realtime do
      paragraphs.each { |p| MarkupStyleRender.new(p, false).parse }
    end
    puts "N=#{N} L=#{L} M=#{M} total=#{(elapsed * 1000).round(2)}ms mean=#{((elapsed / N) * 1_000_000).round(2)}us/paragraph"
  end
end

MarkupStyleRenderBench.run if __FILE__ == $0
