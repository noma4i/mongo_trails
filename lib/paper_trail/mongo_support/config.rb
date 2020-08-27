require 'mongoid'

Mongoid.configure do |config|
  config.clients.default = PaperTrail.config.mongo_config

  config.log_level = :error
end

Mongo::Logger.logger.level = Logger::FATAL
Mongoid.logger.level = Logger::FATAL

Mongoid::QueryCache.enabled = true
