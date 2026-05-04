require 'json'
require 'time'
require 'uri'

require 'Helper'
require 'Request'

# Embeds a single tweet by hitting Twitter's syndication endpoint
# (https://cdn.syndication.twitter.com/tweet-result), the same API
# used by Twitter's own publish widget and by libraries like
# vercel/react-tweet. Returns a markdown blockquote, or `nil` on
# any fetch / parse failure so the caller can fall back to a plain
# link without raising.
module TwitterEmbed
    SYNDICATION_HOST = ENV.fetch('TWITTER_SYNDICATION_HOST', 'https://cdn.syndication.twitter.com').freeze

    # Public: fetches a tweet payload and renders it as markdown.
    # Returns nil if the request, JSON parse, or render fails for any reason.
    def self.render(tweetID, tweetURL, jekyllOpen: '')
        tweet = fetch(tweetID)
        return nil if tweet.nil?
        renderMarkdown(tweet, tweetURL, jekyllOpen: jekyllOpen)
    rescue StandardError
        nil
    end

    def self.fetch(tweetID)
        url = "#{SYNDICATION_HOST}/tweet-result?id=#{tweetID}&token=#{generateToken(tweetID)}&lang=en"
        body = Request.body(Request.URL(url))
        return nil if body.nil? || body.empty?
        JSON.parse(body)
    rescue StandardError
        nil
    end

    # Token derivation matching Twitter's publish widget / react-tweet:
    # https://github.com/vercel/react-tweet/blob/main/packages/api/src/api/fetch-tweet.ts#L8
    #   ((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')
    def self.generateToken(tweetID)
        floatToBase36((tweetID.to_f / 1e15) * Math::PI).gsub(/(0+|\.)/, '')
    end

    # Ruby's Float#to_s has no base argument, so we hand-roll the
    # JS Number#toString(36) format (whole.fractional in base-36).
    def self.floatToBase36(num)
        whole = num.to_i
        frac  = num - whole
        out   = whole.to_s(36)
        return out if frac.zero?

        out += '.'
        16.times do
            break if frac.zero?
            frac *= 36
            digit = frac.to_i
            frac -= digit
            out += digit.to_s(36)
        end
        out
    end

    def self.renderMarkdown(tweet, tweetURL, jekyllOpen: '')
        return nil unless tweet.is_a?(Hash)

        text = expandEntities(tweet)
        name = tweet.dig('user', 'name') || tweet.dig('user', 'screen_name') || 'Twitter User'
        screen = tweet.dig('user', 'screen_name')
        date = formatDate(tweet['created_at'])

        author_link = screen ? "https://twitter.com/#{screen}" : tweetURL

        out = "\n\n"
        out += "■■■■■■■■■■■■■■ \n"
        out += "> **[#{name}](#{author_link})#{jekyllOpen} @ Twitter Says:** \n\n"
        out += "> > #{text} \n\n"
        out += "> **Tweeted at [#{date}](#{tweetURL})#{jekyllOpen}.** \n\n"
        out += "■■■■■■■■■■■■■■ \n\n"
        out
    end

    # Replaces shortened t.co URLs and @-mentions in the tweet body with
    # markdown links. Mirrors the original v1.1 behaviour so existing
    # downstream renderers don't see a behavioural change.
    def self.expandEntities(tweet)
        text = (tweet['text'] || '').dup

        Array(tweet.dig('entities', 'urls')).each do |u|
            short = u['url']
            next if short.nil? || short.empty?
            display  = u['display_url']
            expanded = u['expanded_url'] || short
            label = display && !display.empty? ? display : expanded
            text = text.gsub(short, "[#{label}](#{expanded})")
        end

        Array(tweet.dig('entities', 'user_mentions')).each do |mention|
            screen = mention['screen_name']
            next if screen.nil? || screen.empty?
            # Word-boundary-ish replace so we don't mangle substrings.
            text = text.gsub(/@?#{Regexp.escape(screen)}\b/) do |match|
                prefix = match.start_with?('@') ? '@' : ''
                "#{prefix}[#{screen}](https://twitter.com/#{screen})"
            end
        end

        text
    end

    def self.formatDate(value)
        return '' if value.nil? || value.to_s.empty?
        Time.parse(value.to_s).strftime('%Y-%m-%d %H:%M:%S')
    rescue ArgumentError
        value.to_s
    end
end
