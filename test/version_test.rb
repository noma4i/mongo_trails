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
end
