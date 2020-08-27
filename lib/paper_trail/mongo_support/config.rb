require "paper_trail/config"

Mongoid.configure do |config|
  config.clients.default = PaperTrail.config.mongo_config
end

Mongo::Logger.logger.level = Logger::INFO
Mongoid::QueryCache.enabled = true
