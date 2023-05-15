# frozen_string_literal: true

require "zeitwerk"
Zeitwerk::Loader.for_gem

begin
  require "dotenv/load"
rescue LoadError
end

module BaseProjects
  class Error < StandardError; end
  # Your code goes here...
end
