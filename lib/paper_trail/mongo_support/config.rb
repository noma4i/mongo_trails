require 'mongoid'

Mongoid.configure do |config|
  config.clients.default = PaperTrail.config.mongo_config

  config.log_level = :error
end

Mongoid.logger.level = Logger::FATAL
Mongoid::QueryCache.enabled = false
