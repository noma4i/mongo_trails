# frozen_string_literal: true

module MongoTrails
  # Paper Trail event of the version recorded when a soft-deleted record is restored (RecordTrail#record_restore)
  RESTORE_EVENT = 'restore'

  # Records a 'restore' version when a Paranoia model is restored. Paranoia restores with update_columns,
  # which Paper Trail never sees, so the version history would otherwise jump from 'destroy' to the next update.
  #
  #   class Post < ActiveRecord::Base
  #     acts_as_paranoid
  #     has_paper_trail
  #     include MongoTrails::Restorable
  #   end
  #
  # Include it after acts_as_paranoid, which defines the restore callbacks. The version's changes are the columns
  # Paranoia writes on restore (paranoia_restore_attributes), from their deleted values to the restored ones.
  # Paranoia runs the callbacks for associated records outside the recovery window too, so only a record that
  # was actually restored gets a version.
  module Restorable
    extend ActiveSupport::Concern

    included do
      before_restore :remember_mongo_trails_deleted_attributes
      after_restore :record_mongo_trails_restore
    end

    private

    def remember_mongo_trails_deleted_attributes
      @mongo_trails_deleted_attributes = paranoia_destroyed? ? attributes.slice(*mongo_trails_restore_columns) : nil
    end

    def record_mongo_trails_restore
      deleted_attributes = @mongo_trails_deleted_attributes
      @mongo_trails_deleted_attributes = nil
      return if deleted_attributes.nil? || paranoia_destroyed?

      paper_trail.record_restore(deleted_attributes.to_h { |column, value| [column, [value, self[column]]] })
    end

    def mongo_trails_restore_columns
      send(:paranoia_restore_attributes).keys.map(&:to_s)
    end
  end
end
