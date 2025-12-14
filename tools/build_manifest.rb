#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a compact manifest for /devices/**/*.json
# Usage:
#   ruby tools/build_manifest.rb [--root PATH] [--out PATH] [--skip-validate]
#
# Defaults:
#   --root = repo root of this script (../../)
#   --out  = <root>/manifest.json
#
# Runs validate_devices.rb before building unless --skip-validate is passed.

require "json"
require "digest"
require "time"
require "optparse"
require "pathname"

options = {
  root: Pathname.new(__dir__).join("..").expand_path.to_s,
  out: nil,
  skip_validate: false
}

OptionParser.new do |opts|
  opts.on("--root PATH", "Repo root (default: parent of tools/)") { |v| options[:root] = v }
  opts.on("--out PATH", "Output manifest path (default: <root>/manifest.json)") { |v| options[:out] = v }
  opts.on("--skip-validate", "Skip device validation") { options[:skip_validate] = true }
end.parse!

root = Pathname.new(options[:root]).expand_path
out_path = options[:out] ? Pathname.new(options[:out]).expand_path : root.join("manifest.json")

devices_dir = root.join("devices")
abort "ERR: devices directory not found: #{devices_dir}" unless devices_dir.exist?

# Run validation first unless skipped
unless options[:skip_validate]
  validate_script = Pathname.new(__dir__).join("validate_devices.rb")
  if validate_script.exist?
    puts "Running device validation..."
    result = system("ruby", validate_script.to_s, "--root", root.to_s)
    unless result
      abort "ERR: Device validation failed. Fix errors or use --skip-validate to bypass."
    end
    puts
  else
    warn "WARN: validate_devices.rb not found, skipping validation"
  end
end

def sha256_hex(io)
  digest = Digest::SHA256.new
  while (chunk = io.read(1024 * 1024))
    digest.update(chunk)
  end
  digest.hexdigest
end

entries = []

Dir.glob(devices_dir.join("**/*.json").to_s).sort.each do |fp|
  path = Pathname.new(fp)
  rel  = path.relative_path_from(root).to_s # "devices/vendor/product.json"
  parts = rel.split(File::SEPARATOR)

  # Expect: ["devices", vendor, "product.json"]
  if parts.size < 3
    warn "WARN: unexpected path shape (skipping): #{rel}"
    next
  end

  vendor  = parts[1].to_s
  file    = parts[2].to_s
  product = file.sub(/\.json\z/, "")

  # Read JSON to get version from implementationVersion
  json = JSON.parse(File.read(path))
  version = json["implementationVersion"].to_s

  # Read & hash
  size_bytes = path.size
  sha = File.open(path, "rb") { |io| sha256_hex(io) }

  receives  = Array(json["receives"]).select { |s| s.is_a?(String) }
  transmits = Array(json["transmits"]).select { |s| s.is_a?(String) }
  cc_count  = Array(json["controlChangeCommands"]).size
  nrpn_count = Array(json["nrpnCommands"]).size
  x_pc = json["x_pc"].is_a?(Hash) ? json["x_pc"] : nil

  slug = "#{vendor}.#{product}@#{version}"

  entries << {
    "slug" => slug,
    "vendor" => vendor,
    "product" => product,
    "version" => version,
    "path" => rel,
    "sha256" => sha,
    "size" => size_bytes,
    "receives" => receives,
    "transmits" => transmits,
    "ccCount" => cc_count,
    "nrpnCount" => nrpn_count,
    "x_pc" => x_pc
  }.compact
end

manifest = {
  "schema" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "count" => entries.size,
  "devices" => entries
}

# Stable JSON (sorted keys, 2-space indent, LF endings)
json_str = JSON.pretty_generate(manifest, indent: "  ")
# Collapse simple arrays onto single lines
json_str = json_str.gsub(/\[\s+\]/, "[]")
json_str = json_str.gsub(/\[\s+"([^"]+)"\s+\]/, '["\1"]')
File.write(out_path, json_str.gsub(/\r\n/, "\n"))

puts "Wrote #{out_path} (#{entries.size} devices)"
