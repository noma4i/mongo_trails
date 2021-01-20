# frozen_string_literal: true

require "paper_trail"
require "mongo_trails/config"
require "mongo_trails/model_config"
require "mongo_trails/version_concern"

ActiveSupport.on_load(:active_record) do
  require "mongo_trails/mongo_support/version"
end
