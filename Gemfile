source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read(File.join(__dir__, ".ruby-version")).strip.sub("ruby-", "")

gem "zeitwerk"
gem "bundle-audit"
gem "amazing_print"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "dotenv"
  gem "irb"
end

group :development do
  gem "standard"
  gem "lefthook"
end

group :test do
  gem "simplecov", require: false
end
