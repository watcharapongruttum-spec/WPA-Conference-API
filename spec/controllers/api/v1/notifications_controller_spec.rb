require "rails_helper"

RSpec.describe Api::V1::NotificationsController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "GET /api/v1/notifications" do
    it "returns list of notifications" do
      get "/api/v1/notifications", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    it "returns 401 without token" do
      get "/api/v1/notifications"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/notifications/unread_count" do
    it "returns unread count" do
      get "/api/v1/notifications/unread_count", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("unread_count")
    end
  end

  describe "PATCH /api/v1/notifications/mark_all_as_read" do
    it "marks all as read" do
      patch "/api/v1/notifications/mark_all_as_read", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end
end
