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

`PaperTrail.config.enable_integer_id = true` - Give every version a sequential `integer_id` from a per-collection counter, and order previous/next versions by it. With `false` no counter is used, `integer_id` stays empty and versions are ordered by `created_at`. The first write to a collection with no counter scans the whole collection for its highest `integer_id`, which is expensive on large collections (and on DocumentDB, where no index serves it).

`PaperTrail.config.on_write_error = nil` - A callable receiving `(error, version)` when a version write fails because MongoDB is unreachable or drops the connection (`MongoTrails::Version::WRITE_ERRORS`). Inside a transaction versions are written from the after-commit callbacks, so a raising write skips every after-commit callback behind it; a handler lets them run. Without a handler the error raises. Other errors always raise.

```ruby
PaperTrail.config.on_write_error = lambda do |error, version|
  ErrorReporter.report(error, item_type: version.item_type, item_id: version.item_id)
  version.enqueue_write unless PaperTrail.config.enable_sidekiq # retry through Sidekiq
end
```

`PaperTrail::WriteVersionWorker` rebuilds the queued version with `MongoTrails::Version.rebuild` (its `_id`, `created_at` and metadata are kept, `#initialize` is not run again), and treats a version whose `_id` is already stored as written, so a retried write is safe.

`MongoTrails::Version.bulk_insert(versions)` - Inserts many versions in one `insert_many`, allocating their `integer_id`s in one counter update when `enable_integer_id` is on.

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
