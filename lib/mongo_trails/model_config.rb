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
  end
end
