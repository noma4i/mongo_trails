# frozen_string_literal: true

require 'test_helper'

class TransactionHandlingTest < Minitest::Test
  def setup
    PaperTrail.request.whodunnit = 'Andy Stewart'
    PaperTrail.config.enable_sidekiq = false
    [User, Comment].map(&:delete_all)
    Mongoid.purge!
  end

  def test_on_update_creates_version_if_transaction_completed
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.update!(name: 'Arnold Schwarzenegger')
    end

    assert_equal 2, user.versions.count
  end

  def test_save_version_persists_immediately_without_an_active_record_transaction
    user = User.create!(name: 'John Doe')
    version = MongoTrails::Version.new(
      item: user,
      event: 'update',
      object: { 'name' => 'John Doe' },
      object_changes: { 'name' => ['John Doe', 'Jackie Chan'] }
    )

    version_count = user.versions.count
    version.save_version

    assert_equal version_count + 1, user.versions.count
  end

  def test_on_update_accumulates_many_updates_on_the_same_instance
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      PaperTrail.request.whodunnit = 'automation-1'
      user.update!(name: 'Arnold Schwarzenegger')
      user.update!(title: 'Governor')
      PaperTrail.request.whodunnit = 'automation-3'
      user.update!(name: 'Jackie Chan')
    end

    assert_equal 2, user.versions.count
    assert_equal(
      {
        'name' => ['John Doe', 'Jackie Chan'],
        'title' => [nil, 'Governor']
      },
      user.versions.where(event: 'update').sole.object_changes
    )
    assert_equal 'automation-3', user.versions.where(event: 'update').sole.whodunnit
  end

  def test_distinct_instances_stay_separate_when_first_saved_instance_runs_commit_callbacks
    with_first_saved_instance_callbacks(true) { assert_distinct_instance_versions }
  end

  def test_distinct_instances_stay_separate_when_last_saved_instance_runs_commit_callbacks
    with_first_saved_instance_callbacks(false) { assert_distinct_instance_versions }
  end

  def test_repeated_distinct_instance_writes_keep_each_writer_and_change_separate
    user = User.create!(name: 'John Doe')

    ActiveRecord::Base.transaction do
      update_as(user, 'automation-1-round-1', name: 'A1 round 1')
      update_as(user, 'automation-2-round-1', title: 'A2 round 1')
      update_as(user, 'automation-1-round-2', name: 'A1 round 2')
      update_as(user, 'automation-2-round-2', title: 'A2 round 2')
    end

    versions = user.versions.where(event: 'update').to_a
    assert_equal 4, versions.count
    assert_equal(
      %w[automation-1-round-1 automation-2-round-1 automation-1-round-2 automation-2-round-2],
      versions.map(&:whodunnit)
    )
    assert_equal [%w[name], %w[title], %w[name], %w[title]], versions.map(&:object_changes).map(&:keys)
  end

  def test_nested_transaction_rollback_restores_the_outer_propagation
    user = User.create!(name: 'John Doe')

    ActiveRecord::Base.transaction do
      PaperTrail.request.whodunnit = 'outer-writer'
      user.update!(name: 'Arnold Schwarzenegger')

      ActiveRecord::Base.transaction(requires_new: true) do
        PaperTrail.request.whodunnit = 'rolled-back-writer'
        user.update!(title: 'Governor')
        raise ActiveRecord::Rollback
      end
    end

    version = user.versions.where(event: 'update').sole
    assert_equal({ 'name' => ['John Doe', 'Arnold Schwarzenegger'] }, version.object_changes)
    assert_equal 'outer-writer', version.whodunnit
  end

  def test_nested_transaction_commit_keeps_the_merged_propagation
    user = User.create!(name: 'John Doe')

    ActiveRecord::Base.transaction do
      PaperTrail.request.whodunnit = 'outer-writer'
      user.update!(name: 'Arnold Schwarzenegger')

      ActiveRecord::Base.transaction(requires_new: true) do
        PaperTrail.request.whodunnit = 'inner-writer'
        user.update!(title: 'Governor')
      end
    end

    version = user.versions.where(event: 'update').sole
    assert_equal(
      { 'name' => ['John Doe', 'Arnold Schwarzenegger'], 'title' => [nil, 'Governor'] },
      version.object_changes
    )
    assert_equal 'inner-writer', version.whodunnit
  end

  def test_on_update_does_not_create_version_if_transaction_not_completed
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.update!(name: 'Arnold Schwarzenegger')
      raise ActiveRecord::Rollback
    end

    assert_equal 1, user.versions.count

    user.reload.update!(name: 'Chuck Norris')
    assert_equal 2, user.versions.count
    assert_equal ['John Doe', 'Chuck Norris'], user.versions.where(event: 'update').sole.object_changes['name']
  end

  def test_on_create_creates_version_if_transaction_completed
    assert_equal 0, MongoTrails::Version.count

    user = nil
    ActiveRecord::Base.transaction do
      user = User.create!(name: 'Arnold Schwarzenegger')
    end

    assert_equal 1, user.versions.count
  end

  def test_on_update_after_create_is_folded_into_the_create_version
    user = nil

    ActiveRecord::Base.transaction do
      user = User.create!(name: 'John Doe')
      user.update!(name: 'Jackie Chan', title: 'Actor')
    end

    assert_equal ['create'], user.versions.pluck(:event)
    assert_equal(
      {
        'id' => [nil, user.id],
        'name' => [nil, 'Jackie Chan'],
        'title' => [nil, 'Actor']
      },
      user.versions.sole.object_changes.except('created_at', 'updated_at')
    )
  end

  def test_on_create_does_not_create_version_if_transaction_not_completed
    assert_equal 0, MongoTrails::Version.count

    ActiveRecord::Base.transaction do
      User.create!(name: 'Arnold Schwarzenegger')
      raise ActiveRecord::Rollback
    end

    assert_equal 0, MongoTrails::Version.count
  end

  def test_on_destroy_creates_version_if_transaction_completed
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.destroy!
    end

    assert_equal 2, user.versions.count
  end

  def test_on_destroy_does_not_create_version_if_transaction_not_completed
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.destroy!
      raise ActiveRecord::Rollback
    end

    assert_equal 1, user.versions.count
  end

  def test_on_destroy_keeps_writer_whodunnit_when_request_changes_before_commit
    user = User.create!(name: 'John Doe')

    ActiveRecord::Base.transaction do
      PaperTrail.request.whodunnit = 'deleter'
      user.destroy!
      PaperTrail.request.whodunnit = 'someone-else'
    end

    destroy_version = user.versions.where(event: 'destroy').sole
    assert_equal 'deleter', destroy_version.whodunnit
  end

  def test_version_saved_even_when_other_after_commit_raises
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    User.after_commit { raise 'boom from other callback' }

    assert_raises(RuntimeError) do
      ActiveRecord::Base.transaction do
        user.update!(name: 'Arnold Schwarzenegger')
      end
    end

    assert_equal 2, user.versions.count
  ensure
    User.reset_callbacks(:commit)
  end

  def test_all_versions_saved_when_callback_raises_mid_transaction
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    User.after_commit { raise 'boom from other callback' }

    assert_raises(RuntimeError) do
      ActiveRecord::Base.transaction do
        user.update!(name: 'Arnold Schwarzenegger')
        user.update!(title: 'Governor')
        user.update!(name: 'Jackie Chan')
        user.update!(title: 'Actor')
        user.update!(name: 'Bruce Lee')
      end
    end

    versions = user.versions.where(event: 'update').to_a
    assert_equal 1, versions.count
    assert_equal(
      {
        'name' => ['John Doe', 'Bruce Lee'],
        'title' => [nil, 'Actor']
      },
      versions.sole.object_changes
    )
  ensure
    User.reset_callbacks(:commit)
  end

  private

  def with_first_saved_instance_callbacks(value)
    original = ActiveRecord::Base.run_commit_callbacks_on_first_saved_instances_in_transaction
    ActiveRecord::Base.run_commit_callbacks_on_first_saved_instances_in_transaction = value
    yield
  ensure
    ActiveRecord::Base.run_commit_callbacks_on_first_saved_instances_in_transaction = original
  end

  def assert_distinct_instance_versions
    user = User.create!(name: 'John Doe')

    ActiveRecord::Base.transaction do
      update_as(user, 'automation-1', name: 'Arnold Schwarzenegger')
      update_as(user, 'automation-2', title: 'Governor')
    end

    versions = user.versions.where(event: 'update').to_a
    assert_equal 2, versions.count
    assert_equal({ 'name' => ['John Doe', 'Arnold Schwarzenegger'] }, versions[0].object_changes)
    assert_equal({ 'title' => [nil, 'Governor'] }, versions[1].object_changes)
    assert_equal %w[automation-1 automation-2], versions.map(&:whodunnit)
  end

  def update_as(user, writer, changes)
    PaperTrail.request.whodunnit = writer
    User.find(user.id).update!(changes)
  end
end
