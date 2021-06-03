# frozen_string_literal: true

module PaperTrail
  class WriteVersionWorker
    include Sidekiq::Worker

    def perform(obj)
      MongoTrails::Version.new(obj).save!
    end
  end
end
