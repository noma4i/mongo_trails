# frozen_string_literal: true

require 'mongoid'
require 'autoinc'

begin
  require 'sidekiq'
  require 'mongo_trails/mongo_support/write_version_worker'
  require 'mongo_trails/mongo_support/criteria'
rescue LoadError
  # Continue without Sidekiq
end

class AutoIncrementCounters
  include Mongoid::Document
end

PaperTrail.config.has_paper_trail_defaults = { versions: { class_name: 'MongoTrails::Version' } }

module MongoTrails
  class Version
    class << self
      def find(id)
        find_by(integer_id: id)
      end

      def prefix_map
        (PaperTrail.config.mongo_prefix.is_a?(Proc) && PaperTrail.config.mongo_prefix.call) || 'paper_trail'
      end

      def table_name; end

      def abstract_class?
        false
      end

      def columns_hash
        fields
      end

      def column_names
        fields.keys
      end

      def belongs_to(_name, _options = {}, &block); end

      def validates_presence_of(_name); end

      def after_create(_name); end
    end

    include PaperTrail::VersionConcern
    include Mongoid::Document
    include Mongoid::Autoinc

    store_in collection: -> { "#{MongoTrails::Version.prefix_map}_versions" }

    field :item_type, type: String
    field :item_id, type: String
    field :event, type: String
    field :whodunnit, type: String
    field :object, type: Hash
    field :object_changes, type: Hash
    field :created_at, type: DateTime
    field :integer_id, type: Integer

    index({ item_type: -1, item_id: -1 }, { background: true })

    increments :integer_id, scope: -> { MongoTrails::Version.prefix_map }

    def save_version
      defined?(Sidekiq) && PaperTrail.config.enable_sidekiq ? async_save! : save
    end

    def save_version!
      defined?(Sidekiq) && PaperTrail.config.enable_sidekiq ? async_save! : save!
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
      item_type.constantize.find_by(id: item_id)
    end

    def object=(value)
      super(escape_value(value))
    end

    def object
      unescape_value(super)
    end

    def object_changes
      unescape_value(super)
    end

    def object_changes=(value)
      super(escape_value(value))
    end

    def unescape_value(value)
      value&.deep_transform_keys { |key| parser.unescape(key) }
    end

    def escape_value(value)
      value&.deep_transform_keys { |key| parser.escape(key.to_s, /[$.]/) }
    end

    private

    def parser
      @parser ||= URI::Parser.new
    end

    def async_save!
      worker = defined?(PaperTrail.config.sidekiq_worker.queue) ? PaperTrail.config.sidekiq_worker : PaperTrail::WriteVersionWorker
      args = attributes.as_json
      if worker == PaperTrail::WriteVersionWorker
        worker.set(PaperTrail.config.sidekiq_options).perform_async(args)
      else
        worker.perform_async(args)
      end
    end
  end
end
