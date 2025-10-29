#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify hashes/sizes in manifest.json
# Usage:
#   ruby tools/verify_manifest.rb [--root PATH] [--manifest PATH]

require "json"
require "digest"
require "optparse"
require "pathname"

options = {
  root: Pathname.new(__dir__).join("..").expand_path.to_s,
  manifest: nil
}

OptionParser.new do |opts|
  opts.on("--root PATH", "Repo root (default: parent of tools/)") { |v| options[:root] = v }
  opts.on("--manifest PATH", "Manifest path (default: <root>/manifest.json)") { |v| options[:manifest] = v }
end.parse!

root = Pathname.new(options[:root]).expand_path
manifest_path = options[:manifest] ? Pathname.new(options[:manifest]).expand_path : root.join("manifest.json")
abort "ERR: missing manifest: #{manifest_path}" unless manifest_path.exist?

manifest = JSON.parse(File.read(manifest_path))
devices = Array(manifest["devices"])

def sha256_hex(io)
  digest = Digest::SHA256.new
  while (chunk = io.read(1024 * 1024))
    digest.update(chunk)
  end
  digest.hexdigest
end

errors = 0

devices.each do |d|
  rel = d["path"]
  fp  = root.join(rel)
  unless fp.exist?
    warn "ERR: missing file: #{rel}"
    errors += 1
    next
  end
  size = fp.size
  sha  = File.open(fp, "rb") { |io| sha256_hex(io) }

  if size != d["size"]
    warn "ERR: size mismatch for #{rel}: manifest=#{d['size']} actual=#{size}"
    errors += 1
  end
  if sha != d["sha256"]
    warn "ERR: sha256 mismatch for #{rel}: manifest=#{d['sha256']} actual=#{sha}"
    errors += 1
  end
end

if errors.zero?
  puts "OK: #{devices.size} device file(s) verified"
  exit 0
else
  warn "FAILED: #{errors} error(s)"
  exit 1
end
