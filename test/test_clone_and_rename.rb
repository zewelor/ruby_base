# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class CloneAndRenameTest < Minitest::Test
  GENERATOR = File.expand_path("../clone_and_rename", __dir__)
  DOCKERFILE = <<~DOCKERFILE
    FROM ruby:3.4
    COPY --chown=app:app Gemfile ./
    # Keep template-owned Dockerfile bytes intact.
  DOCKERFILE
  CURRENT_TEMPLATE_DOCKERFILE = <<~DOCKERFILE
    FROM ruby:4.0.9
    COPY --chown=app:app Gemfile /app/
    # Preserve the current template Dockerfile byte-for-byte.
  DOCKERFILE
  SOURCE_CONTENT = "module BaseProjects\n  NAME = 'base_projects'\nend\n"

  def test_clone_renames_project_and_preserves_dockerfile_and_fresh_git_metadata
    assert_generated_project(DOCKERFILE)
  end

  def test_clone_preserves_current_template_dockerfile
    assert_generated_project(CURRENT_TEMPLATE_DOCKERFILE)
  end

  def test_failed_clone_leaves_existing_destination_untouched
    Dir.mktmpdir do |workspace|
      source = File.join(workspace, "source")
      create_repository(source)

      destination = File.join(workspace, "ruby_app")
      create_repository(destination)
      original_path = File.join(destination, "lib", "base_projects.rb")
      FileUtils.mkdir_p(File.dirname(original_path))
      File.write(original_path, SOURCE_CONTENT)
      git("add", ".", chdir: destination)
      git("commit", "--quiet", "-m", "existing target", chdir: destination)
      original_head = git("rev-parse", "HEAD", chdir: destination)[0].strip

      stdout, stderr, status = run_generator(workspace, source, "ruby_app")

      refute status.success?, "generator unexpectedly succeeded:\n#{stdout}#{stderr}"
      assert File.file?(File.join(destination, ".git", "HEAD"))
      assert File.file?(original_path)
      assert_equal SOURCE_CONTENT, File.read(original_path)
      assert_equal original_head, git("rev-parse", "HEAD", chdir: destination)[0].strip
    end
  end

  private

  def assert_generated_project(dockerfile)
    Dir.mktmpdir do |workspace|
      source = File.join(workspace, "source")
      create_repository(source, dockerfile:)

      stdout, stderr, status = run_generator(workspace, source, "ruby_app")
      destination = File.join(workspace, "ruby_app")

      assert status.success?, "generator failed:\n#{stdout}#{stderr}"
      assert_equal dockerfile, File.binread(File.join(destination, "Dockerfile"))
      assert_equal SOURCE_CONTENT.gsub("BaseProjects", "RubyApp").gsub("base_projects", "ruby_app"),
        File.read(File.join(destination, "lib", "ruby_app", "client.rb"))
      assert File.directory?(File.join(destination, ".git"))
      assert_equal "", git("remote", "-v", chdir: destination)[0].strip
      refute git("rev-parse", "--verify", "HEAD", chdir: destination, allow_failure: true)[2].success?
    end
  end

  def create_repository(path, dockerfile: DOCKERFILE)
    FileUtils.mkdir_p(File.join(path, "lib", "base_projects"))
    File.write(File.join(path, "Dockerfile"), dockerfile)
    File.write(File.join(path, "lib", "base_projects", "client.rb"), SOURCE_CONTENT)
    git("init", "--quiet", "-b", "ruby-cli", chdir: path)
    git("config", "user.name", "Ruby Base Test", chdir: path)
    git("config", "user.email", "ruby-base-test@example.invalid", chdir: path)
    git("add", ".", chdir: path)
    git("commit", "--quiet", "-m", "fixture", chdir: path)
  end

  def run_generator(workspace, source, name)
    Open3.capture3(git_url_rewrite(source), RbConfig.ruby, GENERATOR, name, chdir: workspace)
  end

  def git_url_rewrite(source)
    {
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "url.file://#{source}.insteadOf",
      "GIT_CONFIG_VALUE_0" => "https://github.com/zewelor/ruby_base.git"
    }
  end

  def git(*arguments, chdir:, allow_failure: false)
    result = Open3.capture3("git", *arguments, chdir: chdir)
    raise "git #{arguments.join(" ")} failed: #{result[1]}" unless allow_failure || result[2].success?

    result
  end
end
