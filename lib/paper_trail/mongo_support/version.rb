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

    store_in collection: "#{PaperTrail.config.mongo_prefix.call}_versions"

    field :item_type, type: String
    field :item_id, type: Integer
    field :event, type: String
    field :whodunnit, type: String
    field :object, type: Hash
    field :object_changes, type: Hash
    field :created_at, type: DateTime
    field :id, type: Integer

    increments :id, seed: 0

    class << self
      def reset
        Mongoid::QueryCache.clear_cache
      end

      def find(id)
        find_by(id: id)
      end
    end

    def initialize(data)
      item = data.delete(:item)
      if item.present?
        data[:item_type] = item.class.name
        data[:item_id] = item.id
      end
      data[:created_at] = Time.now

      super
    end

    def item
      item_type.constantize.find(item_id)
    end
  end
end
