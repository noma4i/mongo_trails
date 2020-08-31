# frozen_string_literal: true

require "singleton"
require "mongo_trails/serializers/yaml"

module PaperTrail
  # Global configuration affecting all threads. Some thread-specific
  # configuration can be found in `paper_trail.rb`, others in `controller.rb`.
  class Config
    include Singleton

    attr_accessor(
      :association_reify_error_behaviour,
      :object_changes_adapter,
      :serializer,
      :version_limit,
      :has_paper_trail_defaults,
      :mongo_config,
      :mongo_prefix,
      :enable_sidekiq,
      :sidekiq_worker,
      :sidekiq_options
    )

    def initialize
      # Variables which affect all threads, whose access is synchronized.
      @mutex = Mutex.new
      @enabled = true

      # Variables which affect all threads, whose access is *not* synchronized.
      @serializer = PaperTrail::Serializers::YAML
      @has_paper_trail_defaults = {}
      @enable_sidekiq = false
      @sidekiq_options = { queue: :default, retry: true, backtrace: false }
    end

    # Indicates whether PaperTrail is on or off. Default: true.
    def enabled
      @mutex.synchronize { !!@enabled }
    end

    def enabled=(enable)
      @mutex.synchronize { @enabled = enable }
    end
  end
end
