require 'optparse'
require 'fileutils'

require 'ZMediumFetcher'
require 'Helper'
require 'PathPolicy'
require 'Request'
require 'CookieCache'
require 'ChromeAuth'

# All CLI-side concerns for the `ZMediumToMarkdown` executable. Pulled out
# of bin/ so it can be exercised by unit tests without spawning processes.
module CLI
    COOKIE_SETUP_URL = 'https://github.com/ZhgChgLi/ZMediumToMarkdown/wiki/Setting-Up-Medium-Cookies-and-a-Cloudflare-Worker-Proxy'.freeze

    DEFAULT_MEDIUM_HOST = 'https://medium.com/_/graphql'.freeze

    module_function

    def main(argv, output: $stdout, errput: $stderr, cwd: ENV['PWD'] || ::Dir.pwd)
        argv = argv.dup
        argv << '-h' if argv.empty?

        options = parseArgs(argv, errput: errput)
        loadCookies!
        warnAboutMissingSetup(options, errput: errput)
        run(options, cwd, output: output, errput: errput)
    end

    def parseArgs(argv, errput: $stderr)
        options = {}
        parser = OptionParser.new do |opts|
            opts.banner = "Usage: ZMediumToMarkdown [options]"

            opts.on('-s', '--cookie_sid SID', 'Medium logged-in cookie sid value (or set $MEDIUM_COOKIE_SID)') do |v|
                $cookies['sid'] = v
            end

            opts.on('-d', '--cookie_uid UID', 'Medium logged-in cookie uid value (or set $MEDIUM_COOKIE_UID)') do |v|
                $cookies['uid'] = v
            end

            opts.on('--cookie_cf_clearance VALUE', 'Cloudflare cf_clearance cookie value (or set $MEDIUM_COOKIE_CF_CLEARANCE)') do |v|
                $cookies['cf_clearance'] = v
            end

            opts.on('--cookie_cfuvid VALUE', 'Cloudflare _cfuvid cookie value (or set $MEDIUM_COOKIE_CFUVID)') do |v|
                $cookies['_cfuvid'] = v
            end

            opts.on('-x', '--medium_host URL', 'Cloudflare Worker proxy URL for Medium GraphQL (or set $MEDIUM_HOST). Strongly recommended for CI / bulk runs — see the wiki setup guide.') do |v|
                ENV['MEDIUM_HOST'] = v
            end

            opts.on('-u', '--username USERNAME', 'Download all posts from a Medium username') do |v|
                options[:username] = v
            end

            opts.on('-p', '--postURL POST_URL', 'Download a single post URL') do |v|
                options[:postURL] = v
            end

            opts.on('--jekyll', 'Emit Jekyll-friendly output (combine with -u or -p)') do
                options[:jekyll] = true
            end

            opts.on('-j', '--jekyllUsername USERNAME', 'DEPRECATED: use `--jekyll -u USERNAME`') do |v|
                options[:username] = v
                options[:jekyll] = true
                errput.puts '[deprecated] -j/--jekyllUsername is deprecated; use `--jekyll -u USERNAME`.'
            end

            opts.on('-k', '--jekyllPostURL POST_URL', 'DEPRECATED: use `--jekyll -p POST_URL`') do |v|
                options[:postURL] = v
                options[:jekyll] = true
                errput.puts '[deprecated] -k/--jekyllPostURL is deprecated; use `--jekyll -p POST_URL`.'
            end

            opts.on('--stdout', 'Render Markdown of -p/-u directly to stdout. Skips all image/asset downloads (image links stay as remote URLs). Logs and banners go to stderr so stdout stays pure markdown.') do
                options[:stdout] = true
            end

            opts.on('--list', 'With -u <username>, emit one NDJSON line per post (title, url, creator, dates, tags) to stdout. Skips bodies and image downloads.') do
                options[:list] = true
            end

            opts.on('--limit N', Integer, 'Cap the number of posts processed when used with -u (in --stdout or --list mode).') do |v|
                options[:limit] = v
            end

            opts.on('-n', '--new', 'Update to latest version') do
                options[:upgrade] = true
            end

            opts.on('-c', '--clean', 'Remove all downloaded posts data under cwd') do
                options[:clean] = true
            end

            opts.on('-v', '--version', 'Print current ZMediumToMarkdown version') do
                options[:version] = true
            end

            opts.on('--non-interactive', 'Never prompt or open a browser. CI runners auto-detect this; use the flag to force the same behavior on a TTY.') do
                options[:nonInteractive] = true
                ENV['MEDIUM_NO_AUTO_BROWSER'] = '1'
            end

            opts.on('--auth', 'Open Chrome to sign in, capture sid / uid / cf_clearance / _cfuvid into the encrypted cookie cache, and exit. Run once before bulk / scheduled jobs to seed the cache.') do
                options[:auth] = true
            end

            opts.on('-h', '--help', 'Show this help message') do
                options[:help] = opts.to_s
            end
        end

        parser.parse!(argv)
        options
    end

    # Cookie precedence (highest → lowest):
    #   1. CLI flags          (already written to $cookies in parseArgs)
    #   2. Env vars           (MEDIUM_COOKIE_*)
    #   3. On-disk cache      (~/.config/ZMediumToMarkdown/cookies.json)
    # Each layer only fills slots the higher layer left empty.
    def loadCookies!
        loadCookiesFromEnv!
        loadCookiesFromCache!
    end

    def loadCookiesFromEnv!
        $cookies['sid'] = ENV['MEDIUM_COOKIE_SID'] if cookieMissing?('sid') && !ENV['MEDIUM_COOKIE_SID'].to_s.empty?
        $cookies['uid'] = ENV['MEDIUM_COOKIE_UID'] if cookieMissing?('uid') && !ENV['MEDIUM_COOKIE_UID'].to_s.empty?
        $cookies['cf_clearance'] = ENV['MEDIUM_COOKIE_CF_CLEARANCE'] if cookieMissing?('cf_clearance') && !ENV['MEDIUM_COOKIE_CF_CLEARANCE'].to_s.empty?
        $cookies['_cfuvid'] = ENV['MEDIUM_COOKIE_CFUVID'] if cookieMissing?('_cfuvid') && !ENV['MEDIUM_COOKIE_CFUVID'].to_s.empty?
    end

    def loadCookiesFromCache!
        cached = CookieCache.load
        return if cached.empty?
        ChromeAuth::TARGET_COOKIES.each do |name|
            value = cached[name]
            next if value.to_s.empty?
            $cookies[name] = value if cookieMissing?(name)
        end
    end

    def cookieMissing?(name)
        return true unless defined?($cookies) && $cookies.is_a?(Hash)
        $cookies[name].to_s.empty?
    end

    def cookiesPresent?
        !cookieMissing?('sid') || !cookieMissing?('uid')
    end

    # Worker proxy is "configured" when MEDIUM_HOST is set to something
    # other than the default upstream Medium URL — i.e. user pointed it
    # at their own Cloudflare Worker (or another proxy).
    def proxyConfigured?
        host = ENV['MEDIUM_HOST'].to_s
        !host.empty? && host != DEFAULT_MEDIUM_HOST
    end

    # Only warn when the invocation will actually hit Medium — skip for
    # --version, --clean, --help, --new.
    def warnAboutMissingSetup(options, errput: $stderr)
        return unless willHitMedium?(options)

        missingCookies = !cookiesPresent?
        missingProxy   = !proxyConfigured?
        return if !missingCookies && !missingProxy

        errput.puts buildSetupBanner(missingCookies: missingCookies,
                                     missingProxy: missingProxy)
    end

    def willHitMedium?(options)
        !options[:postURL].nil? || !options[:username].nil?
    end

    # One-line warning. The wiki has the actual setup steps; we just
    # nudge the user toward it instead of dumping a wall of guidance.
    def buildSetupBanner(missingCookies:, missingProxy:)
        missing = []
        missing << 'Medium cookies (sid / uid)' if missingCookies
        missing << 'Cloudflare Worker proxy (MEDIUM_HOST)' if missingProxy
        return '' if missing.empty?

        "⚠  Missing #{missing.join(' / ')}. Medium / Cloudflare may block the run. Setup guide: #{COOKIE_SETUP_URL}"
    end

    def run(options, cwd, output: $stdout, errput: $stderr)
        if options[:help]
            output.puts options[:help]
            return
        end

        if options[:version]
            output.puts "Version:#{Helper.getLocalVersion()}"
            Helper.printNewVersionMessageIfExists()
            return
        end

        if options[:clean]
            outputFilePath = PathPolicy.new(cwd, "")
            FileUtils.rm_rf(Dir[outputFilePath.getAbsolutePath(nil)])
            output.puts "All downloaded posts data has been removed."
            Helper.printNewVersionMessageIfExists()
            return
        end

        if options[:upgrade]
            remote = Helper.getRemoteVersionFromGithub()
            local  = Helper.getLocalVersion()
            if remote && local && remote > local
                Helper.downloadLatestVersion()
            else
                output.puts "You're using the latest version :)"
            end
            return
        end

        if options[:auth]
            runAuth(errput: errput)
            return
        end

        # --stdout / --list path: render to the given output stream, skip
        # all filesystem writes and asset downloads. Progress goes to errput
        # so stdout stays pure markdown / NDJSON for embedding callers.
        # Handled before willHitMedium? so the --list-without-username guard
        # surfaces an error instead of silently no-op'ing.
        if options[:stdout] || options[:list]
            if options[:list] && options[:username].nil?
                errput.puts '--list requires -u/--username'
                return
            end
            return unless willHitMedium?(options)

            fetcher = ZMediumFetcher.new
            fetcher.isForJekyll = options[:jekyll] == true
            fetcher.stdoutIO = output
            fetcher.stdoutMode = true
            fetcher.progress.io = errput

            if options[:list]
                fetcher.listPostsByUsername(options[:username], options[:limit])
            elsif options[:postURL]
                fetcher.downloadPost(options[:postURL], nil, nil)
            elsif options[:username]
                fetcher.downloadPostsByUsername(options[:username], nil, limit: options[:limit])
            end
            return
        end

        return unless willHitMedium?(options)

        fetcher = ZMediumFetcher.new
        fetcher.isForJekyll = options[:jekyll] == true

        targetPolicy = pathPolicyFor(cwd, fetcher.isForJekyll)

        if options[:postURL]
            fetcher.downloadPost(options[:postURL], targetPolicy, nil)
        elsif options[:username]
            fetcher.downloadPostsByUsername(options[:username], targetPolicy, limit: options[:limit])
        end

        Helper.printNewVersionMessageIfExists()
    end

    # `--auth` entry point: drive the Chrome login flow on demand so users
    # can seed the cookie cache before kicking off a bulk / CI job. Errors
    # are surfaced to errput; we never raise — `--auth` is best-effort
    # setup, not a critical path.
    def runAuth(errput: $stderr)
        unless ChromeAuth.available?
            errput.puts <<~MSG
              ⚠  Chrome was not detected, so --auth can't run the auto-login flow.
                 Install Google Chrome (or any Chromium-based browser ferrum can
                 detect), or extract sid / uid manually — see:
                 #{COOKIE_SETUP_URL}
            MSG
            return
        end

        cookies = ChromeAuth.login!(errput: errput)
        if cookies.empty?
            errput.puts '⚠  No cookies were captured. Make sure you finished signing in on a medium.com page before pressing Enter.'
            return
        end
        cookies.each { |k, v| $cookies[k] = v unless v.to_s.empty? }
        errput.puts "✅ Captured #{cookies.keys.join(' / ')} → #{CookieCache.path}"
    rescue StandardError => e
        errput.puts "(Auto-login failed: #{e.class}: #{e.message})"
    end

    # Jekyll mode writes into the cwd (so files land in `_posts/...` and
    # `assets/...` of an existing Jekyll site). Plain mode nests under
    # `Output/` to keep the user's cwd tidy.
    def pathPolicyFor(cwd, isForJekyll)
        if isForJekyll
            PathPolicy.new(cwd, "")
        else
            PathPolicy.new("#{cwd}/Output", "Output")
        end
    end
end
