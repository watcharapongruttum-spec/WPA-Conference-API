require "rails_helper"

RSpec.describe Api::V1::DelegatesController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "GET /api/v1/delegates" do
    it "returns delegate list" do
      get "/api/v1/delegates", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("delegates")
      expect(json).to have_key("total")
    end

    it "returns 401 without token" do
      get "/api/v1/delegates"
      expect(response).to have_http_status(:unauthorized)
    end

    it "filters by keyword" do
      get "/api/v1/delegates", params: { keyword: "xyz_notfound" },
          headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "paginates correctly" do
      get "/api/v1/delegates", params: { page: 1, per_page: 5 },
          headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["per_page"]).to eq(5)
    end
  end

  describe "GET /api/v1/delegates/:id" do
    let(:other) { create(:delegate) }

    it "returns delegate info" do
      get "/api/v1/delegates/#{other.id}", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(other.id)
    end

    it "rejects viewing own profile" do
      get "/api/v1/delegates/#{delegate.id}", headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 for unknown delegate" do
      get "/api/v1/delegates/99999999", headers: json_headers(delegate)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/delegates/:id/qr_code" do
    let(:other) { create(:delegate) }

    it "returns qr_code base64" do
      get "/api/v1/delegates/#{other.id}/qr_code", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("qr_code")
    end
  end
end
