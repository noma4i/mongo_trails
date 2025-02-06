# frozen_string_literal: true

module PaperTrail
  class ModelConfig
    def define_has_many_versions(options)
      options = ensure_versions_option_is_hash(options)
      check_version_class_name(options)
      check_versions_association_name(options)

      @model_class.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{@model_class.versions_association_name}
          #{@model_class.version_class_name.constantize}
            .where(item_type: #{@model_class}).and(item_id: self.id).order(created_at: :asc)
        end
      RUBY
    end
  #
  #   def on_create
  #     @model_class.after_create_commit do |r|
  #       r.paper_trail.record_create if r.paper_trail.save_version?
  #     end
  #     append_option_uniquely(:on, :create)
  #   end
  #
  #   def on_destroy(recording_order = 'before')
  #     assert_valid_recording_order_for_on_destroy(recording_order)
  #     @model_class.after_destroy_commit do |r|
  #       break unless r.paper_trail.save_version?
  #       r.paper_trail.record_destroy(recording_order)
  #     end
  #     append_option_uniquely(:on, :destroy)
  #   end
  #
  #   def on_update
  #     @model_class.before_save do |r|
  #       r.paper_trail.reset_timestamp_attrs_for_update_if_needed
  #     end
  #     @model_class.after_update_commit do |r|
  #       if r.paper_trail.save_version?
  #         r.paper_trail.record_update(
  #           force: false,
  #           in_after_callback: true,
  #           is_touch: false
  #         )
  #       end
  #     end
  #     @model_class.after_update_commit do |r|
  #       r.paper_trail.clear_version_instance
  #     end
  #     append_option_uniquely(:on, :update)
  #   end
  end
end
