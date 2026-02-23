class KeepAliveJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[KeepAlive] #{Time.current}"

    # ping web server ตัวเองผ่าน HTTP
    require 'net/http'
    uri = URI("#{ENV['APP_URL']}/")
    Net::HTTP.get(uri) rescue nil

    KeepAliveJob.set(wait: 25.seconds).perform_later
  end
end