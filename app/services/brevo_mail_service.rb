require 'httparty'

class BrevoMailService
  include HTTParty
  base_uri "https://api.brevo.com/v3"

  def self.send_email(to:, subject:, html:)
    response = post(
      "/smtp/email",
      headers: {
        "api-key" => ENV["BREVO_API_KEY"],
        "Content-Type" => "application/json"
      },
      body: {
        sender: {
          email: "noxterror999@gmail.com",
          name: "WPA Conference"
        },
        to: [{ email: to }],
        subject: subject,
        htmlContent: html
      }.to_json
    )

    Rails.logger.info "Brevo response: #{response.body}"
    response
  end
end
