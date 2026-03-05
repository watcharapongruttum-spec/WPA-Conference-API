require "rails_helper"

RSpec.describe Api::V1::SchedulesController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "GET /api/v1/schedules" do
    it "returns schedule list" do
      get "/api/v1/schedules", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("schedules")
      expect(json).to have_key("total")
    end

    it "returns 401 without token" do
      get "/api/v1/schedules"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/schedules/my_schedule" do
    it "returns ok" do
      allow(Schedule).to receive(:build_my_schedule).and_return({ dates: [], schedules: {} })
      get "/api/v1/schedules/my_schedule", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end
end
