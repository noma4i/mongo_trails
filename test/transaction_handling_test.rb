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

  def test_on_update_many_versions_for_many_updates
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.update!(name: 'Arnold Schwarzenegger')
      user.update!(title: 'Governor')
      user.update!(name: 'Jackie Chan')
    end

    assert_equal 4, user.versions.count
    assert_equal({ 'name' => ['John Doe', 'Arnold Schwarzenegger'] },
                 user.versions.where(event: 'update')[0].object_changes)
    assert_equal({ 'title' => [nil, 'Governor'] }, user.versions.where(event: 'update')[1].object_changes)
    assert_equal({ 'name' => ['Arnold Schwarzenegger', 'Jackie Chan'] },
                 user.versions.where(event: 'update')[2].object_changes)
  end

  def test_on_update_does_not_create_version_if_transaction_not_completed
    user = User.create!(name: 'John Doe')
    assert_equal 1, user.versions.count

    ActiveRecord::Base.transaction do
      user.update!(name: 'Arnold Schwarzenegger')
      raise ActiveRecord::Rollback
    end

    assert_equal 1, user.versions.count
  end

  def test_on_create_creates_version_if_transaction_completed
    assert_equal 0, MongoTrails::Version.count

    user = nil
    ActiveRecord::Base.transaction do
      user = User.create!(name: 'Arnold Schwarzenegger')
    end

    assert_equal 1, user.versions.count
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
    assert_equal 5, versions.count

    assert_equal({ 'name' => ['John Doe', 'Arnold Schwarzenegger'] }, versions[0].object_changes)
    assert_equal({ 'title' => [nil, 'Governor'] }, versions[1].object_changes)
    assert_equal({ 'name' => ['Arnold Schwarzenegger', 'Jackie Chan'] }, versions[2].object_changes)
    assert_equal({ 'title' => %w[Governor Actor] }, versions[3].object_changes)
    assert_equal({ 'name' => ['Jackie Chan', 'Bruce Lee'] }, versions[4].object_changes)
  ensure
    User.reset_callbacks(:commit)
  end
end
