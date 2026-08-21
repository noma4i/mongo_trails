# frozen_string_literal: true

require 'mongoid'
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
        next_integer_ids(1).first
      end

      def next_integer_ids(count, scope: prefix_map)
        return [] if count.to_i <= 0

        counter_id = counter_key(scope)
        ensure_counter_initialized(counter_id, scope)

        counter = AutoIncrementCounters.collection.find(_id: counter_id).find_one_and_update(
          { '$inc' => { sequence: count } },
          upsert: true,
          return_document: :after
        )
        max_integer_id = counter.fetch('sequence')

        ((max_integer_id - count + 1)..max_integer_id).to_a
      end

      def bulk_insert_attributes(version)
        version = version.is_a?(self) ? version : new(version)
        attrs = version.attributes.dup
        attrs.delete('_id') if attrs['_id'].nil?
        attrs
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

      private

      def counter_key(scope)
        "#{name}:#{scope || prefix_map}"
      end

      def ensure_counter_initialized(counter_id, _scope)
        existing_counter = AutoIncrementCounters.collection.find(_id: counter_id).first
        return if existing_counter.present?

        max_id = maximum_existing_integer_id

        AutoIncrementCounters.collection.find(_id: counter_id).find_one_and_update(
          { '$set' => { sequence: max_id } },
          upsert: true,
          return_document: :after
        )
      end

      def maximum_existing_integer_id
        pipeline = [
          { '$match' => {} },
          { '$group' => { _id: nil, max_integer_id: { '$max' => '$integer_id' } } }
        ]
        Version.collection.aggregate(pipeline).first&.dig('max_integer_id').to_i
      end
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

    attr_accessor :mongo_trails_source_item

    def save_version
      schedule_version_persistence(bang: false)
    end

    def save_version!
      schedule_version_persistence(bang: true)
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

    def schedule_version_persistence(bang:)
      return VersionCommitWrap.new { persist_version(self, bang:) }.add_to_transaction unless mongo_trails_source_item

      if (propagation = callback_propagations[event])
        propagation.merge!(self, bang:)
      else
        register_callback_propagation(bang:)
      end
    end

    def callback_propagations
      mongo_trails_source_item.instance_variable_get(:@mongo_trails_callback_propagations) ||
        mongo_trails_source_item.instance_variable_set(:@mongo_trails_callback_propagations, {})
    end

    def register_callback_propagation(bang:)
      propagation = CallbackPropagation.new(mongo_trails_source_item, self, bang:)
      callback_propagations[event] = propagation
      VersionCommitWrap.new(rollback: -> { propagation.clear }) { propagation.persist }.add_to_transaction
    end

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

    def current_time = time_zone&.now || Time.now
    def time_zone = Time.zone

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
