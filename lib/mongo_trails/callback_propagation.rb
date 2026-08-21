# frozen_string_literal: true

module MongoTrails
  class CallbackPropagation
    PRESERVED_ATTRIBUTES = %w[_id item_type item_id event object object_changes integer_id].freeze

    attr_reader :version

    def initialize(source, version, bang:)
      @source = source
      @version = version
      @bang = bang
    end

    def merge!(new_version, bang:)
      merge_changes!(new_version.object_changes)
      copy_latest_metadata!(new_version)
      @bang ||= bang
      self
    end

    def snapshot
      {
        object_changes: version.object_changes.to_h.deep_dup,
        metadata: latest_metadata.deep_dup,
        bang: @bang
      }
    end

    def restore!(snapshot)
      version.object_changes = snapshot.fetch(:object_changes)
      snapshot.fetch(:metadata).each { |attribute, value| version[attribute] = value }
      @bang = snapshot.fetch(:bang)
    end

    def persist
      version.send(:persist_version, version, bang: @bang)
    ensure
      clear
    end

    def clear
      propagations = @source.instance_variable_get(:@mongo_trails_callback_propagations)
      propagations&.delete(version.event) if propagations&.fetch(version.event, nil).equal?(self)
    end

    private

    def merge_changes!(new_changes)
      changes = version.object_changes.to_h.deep_dup

      new_changes.to_h.each do |attribute, values|
        key = attribute.to_s
        changes[key] = merged_values(changes[key], values)
        changes.delete(key) if unchanged?(changes[key])
      end

      version.object_changes = changes
    end

    def merged_values(previous_values, new_values)
      previous_values ? [previous_values.first, new_values.last] : new_values
    end

    def unchanged?(values)
      values.first == values.last
    end

    def copy_latest_metadata!(new_version)
      latest_metadata(new_version).each { |attribute, value| version[attribute] = value }
    end

    def latest_metadata(source = version)
      source.attributes.except(*PRESERVED_ATTRIBUTES)
    end
  end
end
