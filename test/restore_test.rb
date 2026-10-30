# frozen_string_literal: true

require 'test_helper'

ActiveRecord::Schema.define do
  create_table :notes, force: true do |t|
    t.string :body
    t.datetime :deleted_at
  end
end

# Restores the way Paranoia does (restore callbacks in a transaction, update_columns), without depending on it
class Note < ActiveRecord::Base
  define_model_callbacks :restore

  has_paper_trail
  include MongoTrails::Restorable

  attr_accessor :outside_recovery_window

  def soft_destroy!
    paper_trail.record_destroy('before')
    update_columns(deleted_at: Time.current)
  end

  def restore!
    self.class.transaction do
      run_callbacks(:restore) { update_columns(paranoia_restore_attributes) unless outside_recovery_window }
    end
  end

  def paranoia_destroyed?
    !deleted_at.nil?
  end

  private

  def paranoia_restore_attributes
    { deleted_at: nil }
  end
end

class RestoreTest < Minitest::Test
  def setup
    PaperTrail.config.enable_sidekiq = false
    Note.delete_all
    Mongoid.purge!

    PaperTrail.request.whodunnit = 'Andy Stewart'
    @note = Note.create!(body: 'Hello')
    @note.soft_destroy!
  end

  def restore_versions
    @note.versions.where(event: MongoTrails::RESTORE_EVENT).to_a
  end

  def test_records_a_restore_version_with_the_restored_columns
    deleted_at = @note.deleted_at

    @note.restore!

    assert_equal 1, restore_versions.size
    version = restore_versions.first
    assert_equal 'Andy Stewart', version.whodunnit
    deleted_at_change = version.changeset['deleted_at'].map { |value| value&.to_i }
    assert_equal [deleted_at.to_i, nil], deleted_at_change
  end

  def test_restore_version_follows_the_destroy_version
    @note.restore!

    assert_equal %w[create destroy restore], @note.versions.map(&:event)
  end

  def test_records_nothing_when_the_record_stays_deleted
    @note.outside_recovery_window = true

    @note.restore!

    assert_empty restore_versions
  end

  def test_records_nothing_for_a_record_that_was_not_deleted
    note = Note.create!(body: 'Active')

    note.restore!

    assert_empty note.versions.where(event: MongoTrails::RESTORE_EVENT).to_a
  end

  def test_records_nothing_when_paper_trail_is_disabled
    PaperTrail.request(enabled: false) { @note.restore! }

    assert_empty restore_versions
  end

  def test_record_restore_records_the_given_changes
    @note.paper_trail.record_restore('deleted_at' => [Time.current, nil], 'body' => %w[Old Hello])

    assert_equal %w[deleted_at body], restore_versions.first.changeset.keys
  end
end
