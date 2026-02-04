source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "zeitwerk"
group :development, :test do
  gem "debug", platforms: %i[mri]
  gem "irb"
end

group :development do
  gem "amazing_print"
  gem "bundle-audit"
  gem "standard"
  gem "lefthook"
  gem "ruby-lsp", require: false
end

group :test do
  gem "simplecov", require: false
end
