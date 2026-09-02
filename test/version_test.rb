# frozen_string_literal: true

require 'test_helper'

class VersionTest < Minitest::Test
  def test_gemspec_uses_the_gem_version
    gemspec = Gem::Specification.load(File.expand_path('../mongo_trails.gemspec', __dir__))

    assert_equal MongoTrails::VERSION, gemspec.version.to_s
    assert_equal 'https://rubygems.org', gemspec.metadata['allowed_push_host']
    assert_equal 'true', gemspec.metadata['rubygems_mfa_required']
  end

  def setup
    PaperTrail.config.enable_sidekiq = false
    [User, Comment].map(&:delete_all)
    Mongoid.purge!
  end

  def test_incrementing_fields_exposes_integer_id_scope
    scope = MongoTrails::Version.incrementing_fields.dig(:integer_id, :scope)

    refute_nil scope
    assert_equal 'test', MongoTrails::Version.new({}).instance_exec(&scope)
    assert_equal 1, MongoTrails::Version.incrementing_fields.dig(:integer_id, :step)
  end

  def test_next_integer_ids_returns_sequential_ids
    assert_equal [1, 2, 3], MongoTrails::Version.next_integer_ids(3)
    assert_equal [4, 5], MongoTrails::Version.next_integer_ids(2)
  end

  def test_bulk_insert_attributes_preserves_insertable_attributes
    attrs = MongoTrails::Version.bulk_insert_attributes(
      item_type: 'User',
      item_id: '1',
      event: 'create',
      integer_id: 10
    )

    refute_nil attrs['_id']
    assert_equal 10, attrs['integer_id']
    assert_equal 'User', attrs['item_type']
  end

  def test_next_integer_ids_preserves_continuity_from_existing_versions
    user = User.create!(name: 'John Doe')
    user.update!(name: 'Jane Doe')

    AutoIncrementCounters.collection.delete_many({})
    max_existing_id = MongoTrails::Version.max(:integer_id)
    next_ids = MongoTrails::Version.next_integer_ids(2)

    assert_equal max_existing_id + 1, next_ids[0]
    assert_equal max_existing_id + 2, next_ids[1]
  end

  def test_next_integer_ids_allocates_unique_ranges_concurrently
    # Initialize the counter before starting the threads so this exercises the atomic allocation
    # used by concurrent requests after a tenant's first version has established its counter.
    MongoTrails::Version.next_integer_ids(1)

    allocations = Queue.new
    threads = 8.times.map do
      Thread.new { allocations << MongoTrails::Version.next_integer_ids(25) }
    end
    threads.each(&:join)

    ids = 8.times.flat_map { allocations.pop }

    assert_equal 200, ids.size
    assert_equal 200, ids.uniq.size
    assert_equal((2..201).to_a, ids.sort)
  end

  def test_next_integer_ids_initializes_the_counter_atomically_under_concurrency
    ready = Queue.new
    start = Queue.new
    threads = 8.times.map do
      Thread.new do
        ready << true
        start.pop
        MongoTrails::Version.next_integer_ids(25)
      end
    end
    8.times { ready.pop }
    8.times { start << true }

    ids = threads.flat_map(&:value)

    assert_equal 200, ids.size
    assert_equal 200, ids.uniq.size
    assert_equal((1..200).to_a, ids.sort)
  end

  def test_next_integer_ids_recovers_when_a_concurrent_initializer_creates_the_counter
    duplicate_key_error = Mongo::Error::OperationFailure.new(
      'E11000 duplicate key error collection: auto_increment_counters index: _id_',
      nil,
      code: 11_000
    )
    counter_lookup = Object.new.tap do |view|
      view.define_singleton_method(:first) { nil }
    end
    counter_initialization = Object.new.tap do |view|
      view.define_singleton_method(:find_one_and_update) do |*_args, **_kwargs|
        raise duplicate_key_error
      end
    end
    counter_increment = Object.new.tap do |view|
      view.define_singleton_method(:find_one_and_update) do |*_args, **_kwargs|
        { 'sequence' => 1 }
      end
    end
    collection = AutoIncrementCounters.collection
    counter_views = {
      lookup: counter_lookup,
      initialization: counter_initialization,
      increment: counter_increment
    }
    remaining_view_ids = counter_views.keys

    AutoIncrementCounters.stub(:collection, collection) do
      collection.stub(:find, ->(*) { counter_views.fetch(remaining_view_ids.shift) }) do
        assert_equal [1], MongoTrails::Version.next_integer_ids(1)
      end
    end

    assert_empty remaining_view_ids
  end

  def test_next_integer_ids_reraises_other_counter_initialization_failures
    operation_failure = Mongo::Error::OperationFailure.new(
      'Unauthorized',
      nil,
      code: 13
    )
    counter_lookup = Object.new.tap do |view|
      view.define_singleton_method(:first) { nil }
    end
    counter_initialization = Object.new.tap do |view|
      view.define_singleton_method(:find_one_and_update) do |*_args, **_kwargs|
        raise operation_failure
      end
    end
    collection = AutoIncrementCounters.collection
    counter_views = {
      lookup: counter_lookup,
      initialization: counter_initialization
    }
    remaining_view_ids = counter_views.keys

    raised_error = AutoIncrementCounters.stub(:collection, collection) do
      collection.stub(:find, ->(*) { counter_views.fetch(remaining_view_ids.shift) }) do
        assert_raises(Mongo::Error::OperationFailure) do
          MongoTrails::Version.next_integer_ids(1)
        end
      end
    end

    assert_same operation_failure, raised_error
    assert_empty remaining_view_ids
  end
end
