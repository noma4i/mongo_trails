# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require_relative 'lib/mongo_trails/version'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

task default: :test

namespace :release do
  desc 'Validate the gem version and release metadata'
  task :validate do
    version = MongoTrails::VERSION
    specification = Gem::Specification.load(File.expand_path('mongo_trails.gemspec', __dir__))
    abort 'Unable to load mongo_trails.gemspec' unless specification
    unless specification.version.to_s == version
      abort "Gemspec version #{specification.version} does not match #{version}"
    end
    abort 'Gem releases must be restricted to RubyGems.org' unless specification.metadata['allowed_push_host'] == 'https://rubygems.org'
  end
end

# Bundler::GemHelper defines `release`; make validation a mandatory prerequisite before it builds,
# tags, pushes the tag, and publishes the gem.
Rake::Task[:release].enhance(['release:validate'])
