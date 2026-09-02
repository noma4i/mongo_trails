[![CI](https://github.com/noma4i/mongo_trails/actions/workflows/test.yml/badge.svg)](https://github.com/noma4i/mongo_trails/actions/workflows/test.yml)

# PaperTrail to MongoDB storage

## Addon for PaperTrail

Track changes to your models, for auditing or versioning. See how a model looked
at any stage in its lifecycle, revert it to any version, or restore it after it
has been destroyed.

## Limitations

- `PaperTrail-AssociationTracking` are not supported in full.

## How to Use

Add to Gemfile

```ruby
  gem 'mongo_trails', git: 'https://github.com/noma4i/mongo_trails'
```

Create initializer like:

```ruby
PaperTrail.config.mongo_config = { hosts: ['localhost:27017'], database: 'my_test_db' }
PaperTrail.config.mongo_prefix = lambda do
  'my_cool_prefix'
end

require 'mongo_trails/mongo_support/config'
```

Done!

## Config Options

`PaperTrail.config.mongo_config = { hosts: ['localhost:27017'], database: 'my_test_db' }` - Options for MongoDB connection

`PaperTrail.config.mongo_prefix = 'my_versions' # or Lambda` - Versions prefix for MongoDB collection

`PaperTrail.config.enable_sidekiq = false` - Enable Sidekiq to proccess versions
`PaperTrail.config.sidekiq_worker = PaperTrail::WriteVersionWorker` - Worker class
`PaperTrail.config.sidekiq_options = { queue: :default }` - Options for Sidekiq

## Releasing

Update `MongoTrails::VERSION` and all appraisal lockfiles, then validate and release:

```bash
bin/bump-version VERSION
bundle exec rake test
bundle exec rubocop
bundle exec rake release:validate
bundle exec rake release
```

The Bundler release task builds the gem, creates and pushes the `vVERSION` Git tag, and publishes to RubyGems.org. Publishing requires RubyGems credentials with MFA; the gemspec rejects other push hosts.
