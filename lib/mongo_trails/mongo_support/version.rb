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
    # Errors a version write can raise when MongoDB is unreachable or drops the connection. Only these reach
    # PaperTrail.config.on_write_error; anything else (a validation error, a bug) still raises.
    WRITE_ERRORS = [Mongo::Error, IOError, SystemCallError, Timeout::Error].freeze
    DUPLICATE_KEY_ERROR_CODE = 11_000

    class << self
      def find(id)
        integer_id_enabled? ? find_by(integer_id: id) : super
      end

      def integer_id_enabled?
        PaperTrail.config.enable_integer_id != false
      end

      # PaperTrail orders previous/next versions by primary key when it is an integer, which here means integer_id.
      # Without integer_id they are ordered by created_at.
      def primary_key_is_int?
        integer_id_enabled?
      end

      # Rebuilds a version from the JSON of one that was already built (see #enqueue_write), keeping its _id,
      # created_at and metadata. It does not run #initialize, so build-time defaults are not applied a second time.
      def rebuild(attributes)
        document = attributes.to_h.stringify_keys.to_h { |name, value| [name, from_json_value(name, value)] }
        instantiate(document).tap { |version| version.new_record = true }
      end

      def duplicate_key_error?(error)
        error.respond_to?(:code) && error.code == DUPLICATE_KEY_ERROR_CODE
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

      def bulk_insert(versions)
        return [] if versions.empty?

        documents = versions.map { |version| bulk_insert_attributes(version) }
        if integer_id_enabled?
          integer_ids = next_integer_ids(documents.count { |document| document['integer_id'].nil? })
          documents.each { |document| document['integer_id'] ||= integer_ids.shift }
        end
        collection.insert_many(documents)
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

      # as_json turns ObjectIds and times into strings; every other field type survives JSON as is.
      def from_json_value(name, value)
        return value unless value.is_a?(String)

        type = fields[name]&.type
        return BSON::ObjectId.legal?(value) ? BSON::ObjectId.from_string(value) : value if type == BSON::ObjectId
        return (Time.zone || Time).parse(value) if [Time, DateTime].include?(type)

        value
      end

      def counter_key(scope)
        "#{name}:#{scope || prefix_map}"
      end

      def ensure_counter_initialized(counter_id, _scope)
        existing_counter = AutoIncrementCounters.collection.find(_id: counter_id).first
        return if existing_counter.present?

        max_id = maximum_existing_integer_id
        initialize_counter(counter_id, max_id)
      end

      def initialize_counter(counter_id, max_id)
        AutoIncrementCounters.collection.find(_id: counter_id).find_one_and_update(
          { '$setOnInsert' => { sequence: max_id } },
          upsert: true,
          return_document: :after
        )
      rescue Mongo::Error::OperationFailure => e
        # DocumentDB can return E11000 when another writer creates this exact counter after the
        # existence check. The caller can safely increment the counter created by that writer.
        raise unless e.code == 11_000
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

    # Queues the write of this version for PaperTrail::WriteVersionWorker (or the configured sidekiq_worker).
    def enqueue_write
      worker = defined?(PaperTrail.config.sidekiq_worker.queue) ? PaperTrail.config.sidekiq_worker : PaperTrail::WriteVersionWorker
      args = attributes.as_json
      if worker == PaperTrail::WriteVersionWorker
        worker.set(PaperTrail.config.sidekiq_options).perform_async(args)
      else
        worker.perform_async(args)
      end
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
      connection = transaction_connection
      return persist_version(self, bang:) unless connection.transaction_open?
      unless mongo_trails_source_item
        return VersionCommitWrap.new { persist_version(self, bang:) }.add_to_transaction(connection)
      end

      if (propagation = callback_propagation)
        merge_callback_propagation(propagation, connection:, bang:)
      else
        register_callback_propagation(connection:, bang:)
      end
    end

    def transaction_connection
      mongo_trails_source_item ? mongo_trails_source_item.class.connection : ActiveRecord::Base.connection
    end

    def callback_propagation
      return callback_propagations[event] unless event == 'update'

      callback_propagations[event] || callback_propagations['create']
    end

    def callback_propagations
      mongo_trails_source_item.instance_variable_get(:@mongo_trails_callback_propagations) ||
        mongo_trails_source_item.instance_variable_set(:@mongo_trails_callback_propagations, {})
    end

    def register_callback_propagation(connection:, bang:)
      propagation = CallbackPropagation.new(mongo_trails_source_item, self, bang:)
      callback_propagations[event] = propagation
      VersionCommitWrap.new(rollback: -> { propagation.clear }) { propagation.persist }.add_to_transaction(connection)
    end

    def merge_callback_propagation(propagation, connection:, bang:)
      snapshot = propagation.snapshot
      VersionCommitWrap.new(rollback: -> { propagation.restore!(snapshot) }) {}.add_to_transaction(connection)
      propagation.merge!(self, bang:)
    end

    def assign_integer_id
      return unless self.class.integer_id_enabled?

      self.integer_id ||= self.class.next_integer_id
    end

    def normalize_created_at(value)
      return value if value.is_a?(Time) || value.is_a?(DateTime)
      return current_time if value.nil?

      parse_time(value)
    rescue ArgumentError
      current_time
    end

    # Inside a transaction this runs from VersionCommitWrap#committed!, among the source record's after-commit
    # callbacks, so an error raised here skips every callback queued behind it. PaperTrail.config.on_write_error
    # receives the connection errors instead of letting them raise; without a handler they raise as before.
    def persist_version(version, bang: false)
      return version.enqueue_write if sidekiq_enabled?

      bang ? version.save! : version.save
    rescue *WRITE_ERRORS => e
      handler = PaperTrail.config.on_write_error
      raise unless handler

      handler.call(e, version)
      nil
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

    # Kept for callers of the old private name; use #enqueue_write.
    alias async_save! enqueue_write
  end
end
