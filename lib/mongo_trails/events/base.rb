module PaperTrail
  module Events
    class Base
      def load_changes_in_latest_version
        changes = if @in_after_callback
          @record.saved_changes
        else
          @record.changes
        end

        changes.delete_if { |_k, v|
          v.is_a?(Array) && v.size > 1 && v.last.is_a?(Hash) && v.uniq.size == 1
        }
      end
    end
  end
end
