source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "zeitwerk"
gem "bundle-audit"
gem "amazing_print"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "irb"
end

group :development do
  gem "standard"
  gem "lefthook"
  gem "ruby-lsp", require: false
end

group :test do
  gem "simplecov", require: false
end
