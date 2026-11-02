# frozen_string_literal: true

module PaperTrail
  class RecordTrail
    def record_create
      return unless enabled?

      version = build_version_on_create(in_after_callback: true)
      return if exceeds_record_size_limit?(version)

      version.mongo_trails_source_item = @record
      version.save_version!
    end

    def record_destroy(recording_order)
      return unless enabled? && !@record.new_record?

      in_after_callback = recording_order == 'after'
      event = Events::Destroy.new(@record, in_after_callback)
      data = event.data.merge(data_for_destroy)

      version = @record.class.paper_trail.version_class.new(data)
      return if exceeds_record_size_limit?(version)

      version.mongo_trails_source_item = @record
      version.save_version
    end

    def record_update(force:, in_after_callback:, is_touch:)
      return unless enabled?

      version = build_version_on_update(
        force: force,
        in_after_callback: in_after_callback,
        is_touch: is_touch
      )
      return unless version && !exceeds_record_size_limit?(version)

      version.mongo_trails_source_item = @record
      version.save_version
    end

    def record_update_columns(changes)
      return unless enabled?

      save_update_columns_version(changes)
    end

    # Records a 'restore' version for a soft-deleted record brought back outside Paper Trail's callbacks,
    # e.g. by Paranoia, which writes with update_columns. `changes` maps each restored column to
    # [before, after], such as { 'deleted_at' => [deleted_at, nil] }.
    def record_restore(changes)
      return unless enabled?

      save_update_columns_version(changes, event: MongoTrails::RESTORE_EVENT)
    end

    private

    def save_update_columns_version(changes, event: nil)
      data = Events::Update.new(@record, false, false, changes).data.merge(data_for_update_columns)
      data[:event] = event if event
      versions_assoc = @record.send(@record.class.versions_association_name)
      version = versions_assoc.new(data)
      return if exceeds_record_size_limit?(version)

      version.mongo_trails_source_item = @record
      version.save_version
    end

    def exceeds_record_size_limit?(version)
      size_limit = PaperTrail.config.mongo_trails_config&.dig(:record_size_limit)
      size_limit && size_limit.to_i < version.to_json.to_s.bytesize
    end
  end
end
