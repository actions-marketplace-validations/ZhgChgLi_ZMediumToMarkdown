require 'fileutils'
require 'time'

# First-run consent gate for ZMediumToMarkdown.
#
# Workflow (priority high → low):
#   1. CLI flag `--accept-terms` (or `--decline-terms`)  consumed before
#      OptionParser, so it never sees them.
#   2. ENV var ZMTM_TOS_ACCEPTED=1                       persistent CI escape.
#   3. Local marker file ~/.zmediumtomarkdown/.tos-vN    written on first
#      interactive accept.
#   4. Otherwise: print the summary and prompt on a TTY; refuse to run on
#      a non-TTY (so a piped invocation can't accidentally bypass).
#
# Bumping `VERSION` invalidates every existing marker file, forcing every
# user to re-read and re-accept the new Terms.
module Terms
    VERSION       = 'v1'.freeze
    ENV_OPT_IN    = 'ZMTM_TOS_ACCEPTED'.freeze
    ACCEPT_FLAG   = '--accept-terms'.freeze
    DECLINE_FLAG  = '--decline-terms'.freeze

    TERMS_URL   = 'https://github.com/ZhgChgLi/ZMediumToMarkdown/blob/main/TERMS.md'.freeze
    PRIVACY_URL = 'https://github.com/ZhgChgLi/ZMediumToMarkdown/blob/main/PRIVACY.md'.freeze

    module_function

    def acceptDir
        File.join(Dir.home, '.zmediumtomarkdown')
    end

    def acceptPath(version = VERSION)
        File.join(acceptDir, ".tos-#{version}-accepted")
    end

    # Strips --accept-terms / --decline-terms out of argv (in place) before
    # OptionParser sees them. Side effects: writing the marker on accept,
    # SystemExit on decline.
    def consumeFlags!(argv, errput: $stderr)
        if argv.delete(DECLINE_FLAG)
            errput.puts 'Terms declined. Exiting.'
            raise SystemExit.new(2)
        end

        if argv.delete(ACCEPT_FLAG)
            writeAcceptance!
            errput.puts "Terms #{VERSION} accepted (see #{acceptPath})."
        end
    end

    # Block until the user has explicitly accepted these Terms. Called
    # before any network operation (see CLI#main).
    def ensureAccepted!(errput: $stderr, input: $stdin)
        return if alreadyAccepted?

        printSummary(errput)

        unless input.respond_to?(:tty?) && input.tty?
            errput.puts <<~MSG.chomp

                [!] Cannot prompt for consent on a non-interactive stream.
                    Run this command in a terminal once, or set #{ENV_OPT_IN}=1,
                    or pass #{ACCEPT_FLAG} on the command line.
            MSG
            raise SystemExit.new(2)
        end

        errput.print "Type 'yes' to accept and continue: "
        answer = input.gets
        answer = answer.to_s.strip.downcase

        if answer == 'yes' || answer == 'y'
            writeAcceptance!
            errput.puts "Accepted. (Marker written to #{acceptPath})"
        else
            errput.puts 'Declined. Exiting.'
            raise SystemExit.new(2)
        end
    end

    def alreadyAccepted?
        return true if ENV[ENV_OPT_IN].to_s == '1'
        File.exist?(acceptPath)
    end

    def writeAcceptance!
        FileUtils.mkdir_p(acceptDir)
        File.write(acceptPath, "accepted_at: #{Time.now.utc.iso8601}\nversion: #{VERSION}\n")
    rescue StandardError => e
        # Don't crash if the home directory is read-only — env var still works.
        warn "[Terms] Could not write acceptance marker (#{e.class}: #{e.message}). " \
             "Re-prompt will appear next run unless #{ENV_OPT_IN}=1."
    end

    def printSummary(io)
        io.puts <<~MSG
            ────────────────────────────────────────────────────────────────────
            ZMediumToMarkdown — first-run notice  (Terms #{VERSION})
            ────────────────────────────────────────────────────────────────────
            Medium's Terms of Service forbid automated access to its Services,
            including via browser plugins, scripts, and CLI tools like this one.

            Use of this tool may conflict with Medium's ToS. You are using it
            AT YOUR OWN RISK. The author (ZhgChgLi) accepts no liability for
            your use, including any account suspension, IP block, or legal
            claim by Medium or by the original article authors.

            By continuing you agree to:
              • only convert articles you have legitimate access to read,
              • respect the original author's copyright when redistributing,
              • not use this tool for mass scraping or commercial redistribution.

            Read the full Terms : #{TERMS_URL}
            Read the Privacy    : #{PRIVACY_URL}

            (To bypass this prompt non-interactively, set #{ENV_OPT_IN}=1
             or pass #{ACCEPT_FLAG} once.)
            ────────────────────────────────────────────────────────────────────
        MSG
    end

    # One-line reminder used by CLI banners, after the Terms have been
    # accepted. Kept short.
    def acceptedBannerLine
        "ℹ  By using this tool you agreed to the Terms (#{VERSION}) — #{TERMS_URL}"
    end
end
