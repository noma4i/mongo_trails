# frozen_string_literal: true

require 'test_helper'

# Makes MongoTrails::Version writes raise while `failure` is set, the way a dropped MongoDB connection does.
module FailingVersionWrite
  class << self
    attr_accessor :failure
  end

  def save(...)
    FailingVersionWrite.failure ? raise(FailingVersionWrite.failure) : super
  end

  def save!(...)
    FailingVersionWrite.failure ? raise(FailingVersionWrite.failure) : super
  end
end
MongoTrails::Version.prepend(FailingVersionWrite)

# Marks a version built through #initialize, to tell a rebuilt version from a version built again.
module InitializeMarker
  def initialize(data)
    super
    self.whodunnit = 'initialize ran' if Thread.current[:mark_version_initialize]
  end
end
MongoTrails::Version.prepend(InitializeMarker)

class CommittedComment < ActiveRecord::Base
  self.table_name = 'comments'

  class << self
    attr_accessor :committed
  end

  after_commit { self.class.committed << id }
end

class WriteFailureTest < Minitest::Test
  def setup
    PaperTrail.request.whodunnit = 'Andy Stewart'
    PaperTrail.config.enable_sidekiq = false
    [User, Comment].map(&:delete_all)
    Mongoid.purge!
    CommittedComment.committed = []
    @errors = []
  end

  def teardown
    FailingVersionWrite.failure = nil
    Thread.current[:mark_version_initialize] = nil
    PaperTrail.config.on_write_error = nil
    PaperTrail.config.enable_integer_id = true
    PaperTrail.config.sidekiq_worker = nil
  end

  def handle_write_errors
    PaperTrail.config.on_write_error = ->(error, version) { @errors << [error, version] }
  end

  def create_user_and_comment
    ActiveRecord::Base.transaction do
      User.create!(name: 'Bob')
      CommittedComment.create!(body: 'after the user')
    end
  end

  def test_without_a_handler_a_failed_write_raises_and_skips_the_after_commit_callbacks_behind_it
    FailingVersionWrite.failure = Mongo::Error::SocketError.new('connection reset')

    assert_raises(Mongo::Error::SocketError) { create_user_and_comment }
    assert_empty CommittedComment.committed
  end

  def test_the_handler_receives_a_failed_write_and_the_after_commit_callbacks_behind_it_still_run
    handle_write_errors
    FailingVersionWrite.failure = Mongo::Error::SocketError.new('connection reset')

    create_user_and_comment

    assert_equal 1, CommittedComment.committed.size
    error, version = @errors.sole
    assert_kind_of Mongo::Error::SocketError, error
    assert_equal %w[User create], [version.item_type, version.event]
    assert_equal 0, MongoTrails::Version.count
  end

  def test_the_handler_receives_a_dropped_connection_outside_a_transaction
    handle_write_errors
    FailingVersionWrite.failure = EOFError.new('end of file reached')

    User.create!(name: 'Bob')

    assert_kind_of EOFError, @errors.sole.first
  end

  def test_errors_that_are_not_connection_errors_still_raise_with_a_handler
    handle_write_errors
    FailingVersionWrite.failure = ArgumentError.new('a bug')

    assert_raises(ArgumentError) { User.create!(name: 'Bob') }
    assert_empty @errors
  end

  def test_the_handler_can_retry_a_failed_write_through_sidekiq
    PaperTrail.config.on_write_error = ->(_error, version) { version.enqueue_write }
    FailingVersionWrite.failure = Mongo::Error::SocketError.new('connection reset')
    user = User.create!(name: 'Bob')
    FailingVersionWrite.failure = nil

    assert_equal 1, PaperTrail::WriteVersionWorker.jobs.size
    PaperTrail::WriteVersionWorker.drain

    assert_equal ['create'], user.versions.map(&:event)
  end

  def test_rebuild_keeps_the_built_version_and_does_not_build_it_again
    created_at = Time.utc(2026, 10, 2, 0, 6, 46)
    version = MongoTrails::Version.new(item_type: 'User', item_id: '1', event: 'update', whodunnit: 'Bob',
                                       object_changes: { 'name' => %w[a b] }, created_at:)
    Thread.current[:mark_version_initialize] = true

    rebuilt = MongoTrails::Version.rebuild(version.attributes.as_json)

    assert_predicate rebuilt, :new_record?
    assert_equal version.id, rebuilt.id
    assert_equal 'Bob', rebuilt.whodunnit
    assert_equal created_at, rebuilt.created_at.to_time.utc
    assert_equal({ 'name' => %w[a b] }, rebuilt.object_changes)
  end

  def test_the_worker_writes_the_version_with_its_original_created_at
    created_at = Time.utc(2026, 10, 2)
    version = MongoTrails::Version.new(item_type: 'User', item_id: '1', event: 'update', created_at:)

    PaperTrail::WriteVersionWorker.new.perform(version.attributes.as_json)

    assert_equal created_at, MongoTrails::Version.find_by(_id: version.id).created_at.to_time.utc
  end

  def test_the_worker_treats_a_version_that_is_already_written_as_done
    version = MongoTrails::Version.new(item_type: 'User', item_id: '1', event: 'create')
    version.save!

    PaperTrail::WriteVersionWorker.new.perform(version.attributes.as_json)

    assert_equal 1, MongoTrails::Version.where(_id: version.id).count
  end

  def test_without_integer_id_no_counter_is_used
    PaperTrail.config.enable_integer_id = false

    user = User.create!(name: 'Bob')
    user.update!(name: 'Bobby')

    assert_equal [nil, nil], user.versions.map(&:integer_id)
    assert_equal 0, AutoIncrementCounters.count
    refute_predicate MongoTrails::Version, :primary_key_is_int?
    assert_equal user.versions.first, MongoTrails::Version.find(user.versions.first.id)
    assert_equal user.versions.last, user.versions.first.next
  end

  def test_bulk_insert_skips_an_empty_list
    assert_equal [], MongoTrails::Version.bulk_insert([])
    assert_equal 0, AutoIncrementCounters.count
  end

  def test_bulk_insert_allocates_integer_ids
    MongoTrails::Version.bulk_insert([{ item_type: 'User', item_id: '1', event: 'create' },
                                      { item_type: 'User', item_id: '2', event: 'create' }])

    assert_equal [1, 2], MongoTrails::Version.order(integer_id: :asc).map(&:integer_id)
  end

  def test_bulk_insert_without_integer_id
    PaperTrail.config.enable_integer_id = false

    MongoTrails::Version.bulk_insert([{ item_type: 'User', item_id: '1', event: 'create' }])

    assert_equal [nil], MongoTrails::Version.pluck(:integer_id)
    assert_equal 0, AutoIncrementCounters.count
  end
end
