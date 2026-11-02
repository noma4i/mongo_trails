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

## Restores

Paper Trail records `create`, `update` and `destroy`, but a soft-deleted record brought back by [Paranoia](https://github.com/rubysherpas/paranoia) is restored with `update_columns`, which Paper Trail never sees. Include `MongoTrails::Restorable` in a Paranoia model to record a version with event `restore` (`MongoTrails::RESTORE_EVENT`) each time it is restored:

```ruby
class Post < ActiveRecord::Base
  acts_as_paranoid
  has_paper_trail
  include MongoTrails::Restorable # after acts_as_paranoid, which defines the restore callbacks
end
```

The version's changes are the columns Paranoia writes on restore (`paranoia_restore_attributes`), from their deleted values to the restored ones. Associated records Paranoia leaves deleted (outside the recovery window) get no version. Paranoia is not a dependency of this gem.

To record a restore done some other way, call `record.paper_trail.record_restore(changes)` with each restored column mapped to `[before, after]`, for example `{ 'deleted_at' => [deleted_at, nil] }`. Like `record_update_columns`, it does nothing while Paper Trail is disabled and respects the record size limit.

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
