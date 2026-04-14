# frozen_string_literal: true

require 'mongoid'
require 'autoinc'
require 'time'
require 'mongo_trails/mongo_support/version_commit_wrap'

begin
  require 'sidekiq'
  require 'mongo_trails/mongo_support/write_version_worker'
  require 'mongo_trails/mongo_support/criteria'
rescue LoadError
  # Continue without Sidekiq
end

class AutoIncrementCounters
  include Mongoid::Document

  store_in collection: 'auto_increment_counters'

  field :sequence, type: Integer, default: 0
end

PaperTrail.config.has_paper_trail_defaults = { versions: { class_name: 'MongoTrails::Version' } }

module MongoTrails
  class Version
    class << self
      def find(id)
        find_by(integer_id: id)
      end

      def incrementing_fields
        @incrementing_fields ||= {
          integer_id: {
            scope: -> { MongoTrails::Version.prefix_map },
            step: 1
          }
        }
      end

      def prefix_map
        (PaperTrail.config.mongo_prefix.is_a?(Proc) && PaperTrail.config.mongo_prefix.call) || 'paper_trail'
      end

      def next_integer_id
        counter = AutoIncrementCounters.collection.find(_id: "#{name}:#{prefix_map}").find_one_and_update(
          { '$inc' => { sequence: 1 } },
          upsert: true,
          return_document: :after
        )

        counter.fetch('sequence')
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

    before_create :assign_integer_id

    def save_version
      version = self
      VersionCommitWrap.new { persist_version(version) }.add_to_transaction
    end

    def save_version!
      version = self
      VersionCommitWrap.new { persist_version(version, bang: true) }.add_to_transaction
    end

    def initialize(data)
      data = data.to_h.deep_symbolize_keys
      item = data.delete(:item)
      if item.present?
        data[:item_type] = item.class.name
        data[:item_id] = item.id
      end
      data[:created_at] = normalize_created_at(data[:created_at])

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
      value&.deep_transform_keys { |key| parser.unescape(force_utf8(key)) }
    end

    def escape_value(value)
      value&.deep_transform_keys { |key| parser.escape(force_utf8(key.to_s), /[$.]/) }
    end

    private

    def assign_integer_id
      self.integer_id ||= self.class.next_integer_id
    end

    def normalize_created_at(value)
      return value if value.is_a?(Time) || value.is_a?(DateTime)
      return current_time if value.nil?

      parse_time(value)
    rescue ArgumentError
      current_time
    end

    def persist_version(version, bang: false)
      return version.send(:async_save!) if sidekiq_enabled?

      bang ? version.save! : version.save
    end

    def parse_time(value)
      time_zone&.parse(value.to_s) || Time.parse(value.to_s)
    end

    def current_time
      time_zone&.now || Time.now
    end

    def time_zone
      Time.zone
    end

    def sidekiq_enabled?
      defined?(Sidekiq) && PaperTrail.config.enable_sidekiq
    end

    def force_utf8(value)
      value.respond_to?(:force_encoding) ? value.dup.force_encoding('UTF-8') : value
    end

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
