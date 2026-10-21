# frozen_string_literal: true

module PaperTrail
  class WriteVersionWorker
    include Sidekiq::Job

    # The job carries a version that was already built, so it is rebuilt as is rather than built again. A retry after a
    # write whose acknowledgement was lost finds its _id already stored: the version is written, so the job is done.
    def perform(obj)
      MongoTrails::Version.rebuild(obj).save!
    rescue Mongo::Error::OperationFailure => e
      raise unless MongoTrails::Version.duplicate_key_error?(e)
    end
  end
end
