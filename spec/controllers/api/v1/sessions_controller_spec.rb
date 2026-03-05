require "rails_helper"

RSpec.describe Api::V1::SessionsController, type: :request do
  let(:company)  { create(:company) }
  let(:delegate) { create(:delegate, company: company, password: "pass1234", password_confirmation: "pass1234") }

  describe "POST /api/v1/login" do
    it "returns token on valid credentials" do
      post "/api/v1/login", params: { email: delegate.email, password: "pass1234" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("token")
    end

    it "returns 401 on wrong password" do
      post "/api/v1/login", params: { email: delegate.email, password: "wrong" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 on unknown email" do
      post "/api/v1/login", params: { email: "nobody@example.com", password: "pass1234" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/change_password" do
    it "changes password successfully" do
      patch "/api/v1/change_password",
            params: { current_password: "pass1234", new_password: "newPass9", new_password_confirmation: "newPass9" }.to_json,
            headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end

    it "rejects wrong current password" do
      patch "/api/v1/change_password",
            params: { current_password: "wrong", new_password: "newPass9", new_password_confirmation: "newPass9" }.to_json,
            headers: json_headers(delegate)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/forgot_password" do
    it "returns ok for existing email" do
      post "/api/v1/forgot_password", params: { email: delegate.email }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    it "returns ok even for unknown email (no info leak)" do
      post "/api/v1/forgot_password", params: { email: "nobody@example.com" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
    end
  end
end
