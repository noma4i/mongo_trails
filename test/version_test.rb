# frozen_string_literal: true

require 'test_helper'

class VersionTest < Minitest::Test
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
end
