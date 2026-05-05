require 'json'
require 'fileutils'
require 'openssl'

# On-disk cache for Medium / Cloudflare cookies captured by ChromeAuth.
# Stored at ~/.zmediumtomarkdown so subsequent runs can reuse sid/uid
# (long-lived) and ride out a still-valid cf_clearance/_cfuvid without
# prompting again.
#
# Encrypted at rest with AES-256-GCM using a fixed key shipped with the
# gem. The key is constant on purpose — this is *obfuscation against
# casual file-system snoops*, not protection from an attacker who has
# the gem source. The file is also written 0600.
#
# On-disk layout (binary):
#   bytes 0..11   : 12-byte IV     (random per write)
#   bytes 12..27  : 16-byte tag    (GCM auth tag)
#   bytes 28..    : ciphertext
#
# The path can be overridden with ZMEDIUM_COOKIE_CACHE_PATH (used by tests
# and power users who want the cache in a different location).
module CookieCache
    PATH_ENV = 'ZMEDIUM_COOKIE_CACHE_PATH'.freeze
    DEFAULT_BASENAME = '.zmediumtomarkdown'.freeze
    CIPHER  = 'aes-256-gcm'.freeze
    SECRET  = 'r3n2wJAX8o944MqFVZPwirjUGZ9A7mII'.freeze  # 32 bytes → AES-256
    IV_LEN  = 12
    TAG_LEN = 16

    module_function

    def path
        override = ENV[PATH_ENV].to_s
        return override unless override.empty?
        File.join(Dir.home, DEFAULT_BASENAME)
    end

    # Returns hash of cached cookies. Missing file or unreadable / corrupt
    # blob (wrong key, truncated, tampered) returns {} — never raises, so
    # the caller can treat the cache as best-effort.
    def load
        return {} unless File.exist?(path)
        plaintext = decrypt(File.binread(path))
        parsed = JSON.parse(plaintext)
        parsed.is_a?(Hash) ? parsed : {}
    rescue StandardError
        {}
    end

    # Atomic write: encrypt the JSON blob, write to a sibling tmp file at
    # 0600, rename. Best-effort: any IO/encryption error is swallowed
    # (cache is convenience, not source of truth — losing a write should
    # not abort the run).
    def save(hash)
        return unless hash.is_a?(Hash) && !hash.empty?
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp.#{Process.pid}"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY, 0o600) do |f|
            f.write(encrypt(JSON.generate(hash)))
        end
        File.rename(tmp, path)
    rescue StandardError
        File.unlink(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
    end

    def clear
        File.unlink(path) if File.exist?(path)
    rescue Errno::ENOENT
        # already gone
    end

    def encrypt(plaintext)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = SECRET
        iv = cipher.random_iv  # 12 bytes
        cipher.auth_data = ''
        ct = cipher.update(plaintext) + cipher.final
        iv + cipher.auth_tag + ct
    end

    def decrypt(blob)
        raise 'cache blob too short' if blob.nil? || blob.bytesize < IV_LEN + TAG_LEN
        iv  = blob.byteslice(0, IV_LEN)
        tag = blob.byteslice(IV_LEN, TAG_LEN)
        ct  = blob.byteslice(IV_LEN + TAG_LEN, blob.bytesize - IV_LEN - TAG_LEN)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = SECRET
        cipher.iv  = iv
        cipher.auth_tag  = tag
        cipher.auth_data = ''
        cipher.update(ct) + cipher.final
    end
end
