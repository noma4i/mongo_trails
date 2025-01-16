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
end
