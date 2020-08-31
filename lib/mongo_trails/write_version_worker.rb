require 'sidekiq'

class WriteVersionWorker
  include ::Sidekiq::Worker

  sidekiq_options queue: :slow

  def perform(data)
    PaperTrail::Version.new(data).save
  rescue => e
    p e.inspect
    # Rollbar.error(e)
  end
end
