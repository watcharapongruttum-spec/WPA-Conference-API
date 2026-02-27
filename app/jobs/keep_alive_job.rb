class KeepAliveJob < ApplicationJob
  queue_as :default

  # ✅ FIX: กัน job ซ้อนกัน — ถ้ามี job นี้ใน queue อยู่แล้วไม่ enqueue ซ้ำ
  discard_on ActiveJob::DeserializationError

  def perform
    return unless Rails.env.production?

    app_host = ENV.fetch("APP_HOST", nil)
    return unless app_host.present?

    Rails.logger.info "[KeepAlive] #{Time.current}"

    begin
      require "net/http"
      uri = URI("https://#{app_host}/")
      Net::HTTP.get(uri)
    rescue StandardError => e
      Rails.logger.warn "[KeepAlive] ping failed: #{e.message}"
    end

    # ✅ FIX: เช็คว่ามี job นี้ใน queue อยู่แล้วไหม ก่อน enqueue ซ้ำ
    queue = Sidekiq::ScheduledSet.new
    already_scheduled = queue.any? { |j| j["class"] == "KeepAliveJob" }
    return if already_scheduled

    KeepAliveJob.set(wait: 25.seconds).perform_later
  end
end
