require "mongoid"
require "autoinc"

class AutoIncrementCounters
  include Mongoid::Document
end

module PaperTrail
  class Version
    include PaperTrail::VersionConcern
    include Mongoid::Document
    include Mongoid::Autoinc

    store_in collection: ->() { "#{PaperTrail::Version.prefix_map}_versions" }

    field :item_type, type: String
    field :item_id, type: String
    field :event, type: String
    field :whodunnit, type: String
    field :object, type: Hash
    field :object_changes, type: Hash
    field :created_at, type: DateTime
    field :integer_id, type: Integer

    increments :integer_id, scope: -> { PaperTrail::Version.prefix_map }

    def save_version!
      PaperTrail.config.enable_sidekiq ? async_save! : save
    end

    def async_save!
      worker = defined?(PaperTrail.config.sidekiq_worker.queue) ? PaperTrail.config.sidekiq_worker : PaperTrail::WriteVersionWorker

      worker.perform_async(attributes)
    end

    class << self
      def reset
        Mongoid::QueryCache.clear_cache
      end

      def find(id)
        find_by(integer_id: id)
      end

      def prefix_map
        (PaperTrail.config.mongo_prefix.is_a?(Proc) ? PaperTrail.config.mongo_prefix.call : 'paper_trail') || 'paper_trail'
      end
    end

    def initialize(data)
      item = data.delete(:item)
      if item.present?
        data[:item_type] = item.class.name
        data[:item_id] = item.id
      end
      data[:created_at] = Time.zone&.now || Time.now

      super
    end

    def item
      item_type.constantize.find(item_id)
    end
  end
end
