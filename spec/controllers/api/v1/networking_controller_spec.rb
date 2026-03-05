require "rails_helper"

RSpec.describe Api::V1::NetworkingController, type: :request do
  let(:delegate) { create(:delegate) }
  let(:other)    { create(:delegate) }

  describe "GET /api/v1/networking/directory" do
    it "returns delegate list" do
      get "/api/v1/networking/directory", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/networking/my_connections" do
    it "returns connections" do
      get "/api/v1/networking/my_connections", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/networking/pending_requests" do
    it "returns pending requests" do
      get "/api/v1/networking/pending_requests", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/networking/unfriend" do
    it "returns error if not connected" do
      delete "/api/v1/networking/unfriend/#{other.id}",
             headers: json_headers(delegate)
      expect(response).to have_http_status(:not_found)
    end
  end
end
