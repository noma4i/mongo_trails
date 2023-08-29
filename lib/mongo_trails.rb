# frozen_string_literal: true

require 'paper_trail'
require 'paper_trail/version_concern'
require 'paper_trail/model_config'
require 'paper_trail/record_trail'

require 'mongo_trails/config'
require 'mongo_trails/model_config'
require 'mongo_trails/version_concern'
require 'mongo_trails/record_trail'

ActiveSupport.on_load(:active_record) do
  require 'mongo_trails/mongo_support/version'
end
