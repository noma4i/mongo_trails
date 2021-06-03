module PaperTrail
  class RecordTrail
    def record_create
      return unless enabled?

      build_version_on_create(in_after_callback: true).tap do |version|
        version.save_version!
      end
    end

    def record_destroy(recording_order)
      return unless enabled? && !@record.new_record?

      in_after_callback = recording_order == "after"
      event = Events::Destroy.new(@record, in_after_callback)
      data = event.data.merge(data_for_destroy)

      @record.class.paper_trail.version_class.new(data).save_version
    end

    def record_update(force:, in_after_callback:, is_touch:)
      return unless enabled?

      version = build_version_on_update(
        force: force,
        in_after_callback: in_after_callback,
        is_touch: is_touch
      )
      return unless version

      version.save_version
    end

    def record_update_columns(changes)
      return unless enabled?

      event = Events::Update.new(@record, false, false, changes)
      data = event.data.merge(data_for_update_columns)
      versions_assoc = @record.send(@record.class.versions_association_name)

      versions_assoc.new(data).save_version
    end
  end
end
