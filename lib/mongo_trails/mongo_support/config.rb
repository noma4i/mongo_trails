# frozen_string_literal: true

require 'mongoid'

Mongoid.configure do |config|
  config.clients.default = PaperTrail.config.mongo_config

  config.log_level = :error
end

Mongoid::QueryCache.enabled = false
