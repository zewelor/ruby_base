# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

mode = ARGV.fetch(0, "install")
abort "Usage: ruby test/bundle_install_test.rb [install|disabled]" unless %w[install disabled].include?(mode)

def check(condition, message)
  raise message unless condition
end

def run_bundle(environment, *arguments)
  Open3.capture3(environment, "bundle", *arguments)
end

Dir.mktmpdir("ruby-base-bundle-") do |fixture|
  package_dir = File.join(fixture, "package")
  cache_dir = File.join(fixture, "vendor/cache")
  FileUtils.mkdir_p([File.join(package_dir, "lib"), cache_dir])
  File.write(File.join(package_dir, "lib/ruby_base_bundle_probe.rb"), "RUBY_BASE_BUNDLE_PROBE = :installed\n")
  specification = Gem::Specification.new do |gem|
    gem.name = "ruby_base_bundle_probe"
    gem.version = "0.1.0"
    gem.summary = "Isolated bundle installation fixture"
    gem.authors = ["Ruby Base"]
    gem.license = "MIT"
    gem.homepage = "https://example.invalid"
    gem.required_ruby_version = ">= 3.0"
    gem.files = ["lib/ruby_base_bundle_probe.rb"]
  end
  archive = Dir.chdir(package_dir) { Gem::Package.build(specification) }
  archive_path = File.join(cache_dir, archive)
  FileUtils.mv(File.join(package_dir, archive), archive_path)
  gemfile = File.join(fixture, "Gemfile")
  original_gemfile = <<~GEMFILE
    source "file://#{fixture}/unavailable-repository"
    gem "ruby_base_bundle_probe", "0.1.0"
  GEMFILE
  File.write(gemfile, original_gemfile)
  environment = {
    "BUNDLE_GEMFILE" => gemfile,
    "BUNDLE_PATH" => File.join(fixture, "bundle"),
    "BUNDLE_CACHE_PATH" => cache_dir,
    "BUNDLE_IGNORE_CONFIG" => "true",
    "BUNDLE_FROZEN" => "true",
    "BUNDLE_RETRY" => "0"
  }
  output, error, status = run_bundle(environment.merge("BUNDLE_FROZEN" => "false"), "install", "--local")
  check(status.success?, "Fixture preparation failed: #{output}#{error}")
  FileUtils.rm_rf(File.join(fixture, "bundle"))
  lockfile = File.join(fixture, "Gemfile.lock")
  original_lock = File.binread(lockfile)
  command = ["exec", RbConfig.ruby, "-r", "ruby_base_bundle_probe", "-e", "puts RUBY_BASE_BUNDLE_PROBE"]

  output, error, status = run_bundle(environment, *command)
  if mode == "disabled"
    check(!status.success?, "Missing gem unexpectedly became available")
    check(!output.include?("Automatically installing"), "This service attempted to install missing gems")
    check(!File.directory?(File.join(fixture, "bundle", "ruby")), "This service created a bundle")
  else
    check(status.success? && output.lines.map(&:strip).include?("installed"), "Missing gem was not installed: #{output}#{error}")
    check(output.include?("Automatically installing"), "Expected automatic installation on the first command")

    output, error, status = run_bundle(environment.merge("RAILS_ENV" => "production"), *command)
    check(status.success? && output.strip == "installed", "Prepared bundle was not reused: #{output}#{error}")

    File.write(gemfile, original_gemfile.sub('"0.1.0"', '"0.2.0"'))
    _, _, status = run_bundle(environment, *command)
    check(!status.success? && File.binread(lockfile) == original_lock, "Ordinary commands updated changed dependencies")
    File.write(gemfile, original_gemfile)

    FileUtils.rm(lockfile)
    _, _, status = run_bundle(environment, *command)
    check(!status.success? && !File.exist?(lockfile), "Ordinary commands resolved a new lockfile")
    File.binwrite(lockfile, original_lock)

    FileUtils.rm_rf(File.join(fixture, "bundle"))
    FileUtils.rm(archive_path)
    output, error, status = run_bundle(environment, *command)
    check(!status.success?, "Unavailable dependency unexpectedly succeeded")
    check(output.include?("Automatically installing") && !error.empty?, "Installation failure was not visible: #{output}#{error}")
    check(!output.lines.map(&:strip).include?("installed"), "Command ran after installation failed")
  end
  check(File.binread(lockfile) == original_lock, "Ordinary commands changed the lockfile")

  puts "Bundle #{mode} checks passed (missing gem, lockfile and visible failures)."
end
