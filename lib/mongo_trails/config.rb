# frozen_string_literal: true

module PaperTrail
  class Config
    attr_accessor(
      :mongo_config,
      :mongo_prefix,
      :enable_sidekiq,
      :sidekiq_worker,
      :sidekiq_options
    )

    def initialize
      @mutex = Mutex.new
      @enabled = true

      @serializer = PaperTrail::Serializers::YAML
      @has_paper_trail_defaults = {}
      @enable_sidekiq = false
      @sidekiq_options = { queue: :default, retry: true, backtrace: false }
    end
  end
end
