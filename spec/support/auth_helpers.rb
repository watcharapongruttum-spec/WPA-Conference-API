module AuthHelpers
  def auth_headers(delegate)
    payload = { delegate_id: delegate.id, iss: JWT_CONFIG[:issuer] }
    token   = JWT.encode(payload, JWT_CONFIG[:secret], JWT_CONFIG[:algorithm])
    { "Authorization" => "Bearer #{token}" }
  end

  def json_headers(delegate)
    auth_headers(delegate).merge("Content-Type" => "application/json")
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
