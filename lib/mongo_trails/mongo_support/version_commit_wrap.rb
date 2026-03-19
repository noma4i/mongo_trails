module MongoTrails
  class VersionCommitWrap
    def initialize(&callback)
      @callback = callback
      @executed = false
    end

    def has_transactional_callbacks? # rubocop:disable Naming/PredicatePrefix
      true
    end

    def trigger_transactional_callbacks?
      true
    end

    def before_committed!; end

    def rolledback!(*)
      @executed = true
    end

    def committed!(should_run_callbacks: true) # rubocop:disable Lint/UnusedMethodArgument
      return if @executed

      @executed = true
      @callback.call
    end

    def add_to_transaction(*)
      ActiveRecord::Base.connection.add_transaction_record(self)
    end
  end
end
