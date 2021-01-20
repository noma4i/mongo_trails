module PaperTrail
  class WriteVersionWorker
    include Sidekiq::Worker

    def perform(obj)
      PaperTrail::Version.new(obj).save!
    end
  end
end
