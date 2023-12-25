# frozen_string_literal: true

# https://github.com/fxn/zeitwerk#synopsis
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup # ready!

begin
  require "dotenv/load"
# rubocop:disable Lint/SuppressedException
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

module BaseProjects
  class Error < StandardError; end
  # Your code goes here...
end
