source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read(File.join(__dir__, ".ruby-version")).strip.sub("ruby-", "")

gem "zeitwerk"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "faker"
  gem "dotenv"
  gem "pry"
end

group :development do
  gem "lefthook"
  gem "standard"
  gem "bundler-audit"
end

group :test do
  gem "simplecov", require: false
end
