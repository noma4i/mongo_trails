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
end
