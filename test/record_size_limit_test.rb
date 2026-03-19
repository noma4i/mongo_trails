# frozen_string_literal: true

require 'test_helper'

class RecordSizeLimit < Minitest::Test
  def record_size_limit
    1_000_000
  end

  def setup
    PaperTrail.config.enable_sidekiq = false
    PaperTrail.config.mongo_trails_config = { record_size_limit: record_size_limit }
    User.delete_all
    Mongoid.purge!
    PaperTrail.request.whodunnit = 'Andy Stewart'
  end

  def test_create_limit_size_exceeded
    user = User.create(name: 'w' * record_size_limit)

    assert_equal 0, user.versions.count
  end

  def test_create_limit_size_ok
    user = User.create(name: 'w' * (record_size_limit / 2))

    assert_equal 1, user.versions.count
  end

  def test_update_limit_size_exceeded
    user = User.create(name: 'JKVD')
    user.update(name: 'w' * record_size_limit)

    assert_equal 1, user.versions.count
  end

  def test_update_limit_size_ok
    user = User.create(name: 'JKVD')
    user.update(name: 'w' * (record_size_limit / 2))

    assert_equal 2, user.versions.count
  end
end
