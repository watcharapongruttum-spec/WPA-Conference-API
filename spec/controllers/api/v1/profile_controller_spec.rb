require "rails_helper"

RSpec.describe Api::V1::ProfileController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "GET /api/v1/profile" do
    it "returns own profile" do
      get "/api/v1/profile", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(delegate.id)
    end

    it "returns 401 without token" do
      get "/api/v1/profile"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/profile" do
    it "updates name successfully" do
      patch "/api/v1/profile",
            params: { name: "New Name" }.to_json,
            headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("New Name")
    end
  end
end
