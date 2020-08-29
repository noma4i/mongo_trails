[![Build Status](https://travis-ci.com/noma4i/mongo_trails.svg?branch=master)](https://travis-ci.com/noma4i/mongo_trails)

# PaperTrail to MongoDB storage

Based on paper-trail gem `v10.3.1`. All future versions will follow version of the parent Paper Trail gem

Track changes to your models, for auditing or versioning. See how a model looked
at any stage in its lifecycle, revert it to any version, or restore it after it
has been destroyed.

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

## Using Rspec

`require 'mongo_trails/frameworks/rspec'`

API is the same as `paper_trail`
