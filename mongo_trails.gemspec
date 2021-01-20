# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "mongo_trails/compatibility"
require "mongo_trails/version_number"

Gem::Specification.new do |s|
  s.name = "mongo_trails"
  s.version = PaperTrail::VERSION::STRING
  s.platform = Gem::Platform::RUBY
  s.summary = "PaperTrail DropIn replacement to store versions in MongoDB"
  s.description = <<-EOS
PaperTrail DropIn replacement to store version in MongoDB
  EOS
  s.homepage = "https://github.com/noma4i/mongo_trails"
  s.metadata['homepage_uri'] = s.homepage
  s.metadata['source_code_uri'] = s.homepage
  s.authors = ["Alex Tsirel","Ivan Romanyuk"]
  s.email = ["noma4i@gmail.com"]
  s.license = "MIT"

  s.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  s.bindir        = 'exe'
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_dependency "activerecord", ::PaperTrail::Compatibility::ACTIVERECORD_GTE
  s.add_dependency "request_store", "~> 1.1"
  s.add_dependency "mongoid", "< 8"
  s.add_dependency "mongoid-autoinc", "< 7"

  s.add_development_dependency "sidekiq", "< 7"
  s.add_development_dependency "sqlite3", "~> 1.4"
  s.add_development_dependency "appraisal", "~> 2.3"
end
