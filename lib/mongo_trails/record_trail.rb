module PaperTrail
  class RecordTrail
    def record_create
      return unless enabled?

      build_version_on_create(in_after_callback: true).tap do |version|
        return if exceeds_record_size_limit?(version)

        version.save_version!
      end
    end

    def record_destroy(recording_order)
      return unless enabled? && !@record.new_record?

      in_after_callback = recording_order == 'after'
      event = Events::Destroy.new(@record, in_after_callback)
      data = event.data.merge(data_for_destroy)

      version = @record.class.paper_trail.version_class.new(data)
      return if exceeds_record_size_limit?(version)

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

      version.save_version
    end

    def record_update_columns(changes)
      return unless enabled?

      event = Events::Update.new(@record, false, false, changes)
      data = event.data.merge(data_for_update_columns)
      versions_assoc = @record.send(@record.class.versions_association_name)
      version = versions_assoc.new(data)
      return if exceeds_record_size_limit?(version)

      version.save_version
    end

    private

    def exceeds_record_size_limit?(version)
      size_limit = PaperTrail.config.mongo_trails_config&.dig(:record_size_limit)
      size_limit && size_limit.to_i < version.to_json.to_s.bytesize
    end
  end
end
