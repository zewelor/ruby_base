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
  gem "lefthook"
  gem "rubocop-performance"
  gem "ruby-lsp", require: false
  gem "standard"
end
