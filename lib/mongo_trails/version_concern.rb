# frozen_string_literal: true

module PaperTrail
  module VersionConcern
    extend ::ActiveSupport::Concern

    module ClassMethods
      def with_item_keys(item_type, item_id)
        where(item_type: item_type, item_id: item_id)
      end

      def between(start_time, end_time)
        where(:created_at.gt => start_time, :created_at.lt => end_time).order(timestamp_sort_order)
      end

      def timestamp_sort_order(direction = 'asc')
        { created_at: direction.downcase }
      end

      def object_col_is_json?
        true
      end

      def object_changes_col_is_json?
        true
      end

      def preceding_by_id(obj)
        where(:integer_id.lt => obj.integer_id).order(integer_id: :desc)
      end

      def preceding_by_timestamp(obj)
        obj = obj.send(:created_at) if obj.is_a?(self)
        where(:created_at.lt => obj).order(timestamp_sort_order('desc'))
      end

      def subsequent_by_id(version)
        where(:integer_id.gt => version.integer_id).order(integer_id: :asc)
      end

      def subsequent_by_timestamp(obj)
        obj = obj.send(:created_at) if obj.is_a?(self)
        where(:created_at.gt => obj).order(timestamp_sort_order)
      end
    end
  end
end
