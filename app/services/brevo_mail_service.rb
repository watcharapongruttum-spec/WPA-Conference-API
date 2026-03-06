class BrevoMailService
  require "net/http"
  require "uri"
  require "json"

  def self.send_email(to:, subject:, html:)
    url = URI.parse("https://api.brevo.com/v3/smtp/email")

    payload = {
      sender: {
        name: "WPA Conference",
        email: ENV.fetch("BREVO_SENDER_EMAIL", nil)
      },
      to: [
        { email: to }
      ],
      subject: subject,
      htmlContent: html # 🔥 สำคัญมาก
    }

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url.request_uri)
    request["api-key"] = ENV.fetch("BREVO_API_KEY", nil)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    Rails.logger.info "[Brevo] Response: #{response.body}"

    response
  end
end




