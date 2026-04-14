# frozen_string_literal: true

require 'mongoid'

Mongoid.configure do |config|
  config.clients.default = PaperTrail.config.mongo_config

  config.log_level = :error
end

if defined?(Mongo::QueryCache)
  Mongo::QueryCache.enabled = false
elsif defined?(Mongoid::QueryCache)
  Mongoid::QueryCache.enabled = false
end
