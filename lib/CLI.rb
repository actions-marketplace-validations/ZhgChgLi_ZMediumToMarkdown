require 'optparse'
require 'fileutils'

require 'ZMediumFetcher'
require 'Helper'
require 'PathPolicy'
require 'Request'

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
        loadCookiesFromEnv!
        warnAboutMissingSetup(options, errput: errput)
        run(options, cwd, output: output)
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

            opts.on('-x', '--medium_host URL', 'Cloudflare Worker proxy URL for Medium GraphQL (or set $MEDIUM_HOST). Strongly recommended for CI / bulk runs — see the wiki setup guide.') do |v|
                ENV['MEDIUM_HOST'] = v
            end

            opts.on('--miro_medium_host URL', 'Cloudflare Worker proxy URL for Medium image CDN (or set $MIRO_MEDIUM_HOST). Optional companion to --medium_host.') do |v|
                ENV['MIRO_MEDIUM_HOST'] = v
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

            opts.on('-n', '--new', 'Update to latest version') do
                options[:upgrade] = true
            end

            opts.on('-c', '--clean', 'Remove all downloaded posts data under cwd') do
                options[:clean] = true
            end

            opts.on('-v', '--version', 'Print current ZMediumToMarkdown version') do
                options[:version] = true
            end

            opts.on('-h', '--help', 'Show this help message') do
                options[:help] = opts.to_s
            end
        end

        parser.parse!(argv)
        options
    end

    def loadCookiesFromEnv!
        $cookies['sid'] = ENV['MEDIUM_COOKIE_SID'] if cookieMissing?('sid') && !ENV['MEDIUM_COOKIE_SID'].to_s.empty?
        $cookies['uid'] = ENV['MEDIUM_COOKIE_UID'] if cookieMissing?('uid') && !ENV['MEDIUM_COOKIE_UID'].to_s.empty?
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

        errput.puts buildSetupBanner(missingCookies: missingCookies, missingProxy: missingProxy)
    end

    def willHitMedium?(options)
        !options[:postURL].nil? || !options[:username].nil?
    end

    # Builds the dynamic setup-warning banner. Header lists exactly which
    # of (cookies, proxy) is missing so the user can act; body is static
    # guidance covering empirical limits, scenarios, and how to pass each
    # value via flag or env.
    def buildSetupBanner(missingCookies:, missingProxy:)
        lines = []
        lines << '──────────────────────────────────────────────────────────────────────'
        lines << '⚠  Setup notice — your run will work, but reliability is limited.'
        lines << ''
        lines << "What's missing:"
        lines << '  • Medium login cookies (sid / uid).' if missingCookies
        lines << '  • Cloudflare Worker proxy (MEDIUM_HOST not set or still default).' if missingProxy
        lines << ''
        lines << <<~BODY.chomp
          Empirical limits without setup:
            • Without cookies         : Cloudflare blocks after ~10 posts.
            • Without Worker proxy    : Cloudflare blocks after ~25 posts
                                        when running from CI / datacenter IPs.
            • Paywalled posts         : cookies are REQUIRED for full content;
                                        without them you only get the preview.

          Recommended setup:
            • CI / CD (GitHub Actions, cloud runners):
                STRONGLY recommend BOTH cookies AND a Cloudflare Worker proxy.
            • Local machine:
                Cookies recommended for paywalled posts. If a Cloudflare
                challenge appears, the tool will automatically open
                https://medium.com in your browser and prompt you to retry
                once you've cleared it. Set MEDIUM_NO_AUTO_BROWSER=1 to
                opt out and just fail fast.

          Pass cookies via env (preferred — keeps secrets out of shell history):
            MEDIUM_COOKIE_SID=... MEDIUM_COOKIE_UID=... ZMediumToMarkdown -p URL

          Or via flags (fine for one-off local runs):
            ZMediumToMarkdown -p URL -s YOUR_SID -d YOUR_UID

          Pass Cloudflare Worker proxy URL:
            ZMediumToMarkdown -p URL -x https://YOUR-WORKER.workers.dev/_/graphql
            # or via env:  MEDIUM_HOST=https://YOUR-WORKER.workers.dev/_/graphql

          Full setup guide (cookies + Cloudflare Worker proxy):
            #{COOKIE_SETUP_URL}
          ──────────────────────────────────────────────────────────────────────
        BODY
        lines.join("\n")
    end

    def run(options, cwd, output: $stdout)
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

        return unless willHitMedium?(options)

        fetcher = ZMediumFetcher.new
        fetcher.isForJekyll = options[:jekyll] == true

        targetPolicy = pathPolicyFor(cwd, fetcher.isForJekyll)

        if options[:postURL]
            fetcher.downloadPost(options[:postURL], targetPolicy, nil)
        elsif options[:username]
            fetcher.downloadPostsByUsername(options[:username], targetPolicy)
        end

        Helper.printNewVersionMessageIfExists()
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
