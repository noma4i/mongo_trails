# frozen_string_literal: true

require 'test_helper'

class BasicIntegrationTest < Minitest::Test
  def setup
    PaperTrail.config.enable_sidekiq = false

    [User, Comment].map(&:delete_all)
    Mongoid.purge!

    PaperTrail.request.whodunnit = 'Andy Stewart'
    @user = User.create(name: 'Bob')
    [*1..20].each do |i|
      c = @user.comments.find_or_create_by(body: "Hello #{i}")
      c.update!(body: 'Hello again!')
      @user.update!(name: "Bob #{i}")
    end
  end

  def test_version_created
    assert_equal 20, @user.comments.count
    assert_equal 21, @user.versions.count
  end

  def test_changeset
    changeset = { 'name' => ['Bob 19', 'Bob 20'] }

    assert_equal changeset, @user.versions.last.changeset
  end

  def test_versions_getters
    refute_same @user.versions.first, @user.versions.last
    assert_equal 'Bob 19', @user.paper_trail.previous_version.name
  end

  def test_version_next_restore
    MongoTrails::Version.find(1).next.reify.save!
    assert_equal 'Bob', User.first.name
  end

  def test_version_previous_restore
    MongoTrails::Version.find(3).previous.reify.save!

    assert_equal 'Bob', User.first.name
  end
end
