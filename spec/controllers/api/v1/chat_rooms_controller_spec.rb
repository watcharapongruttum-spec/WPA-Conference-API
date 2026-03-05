require "rails_helper"

RSpec.describe Api::V1::ChatRoomsController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "POST /api/v1/chat_rooms" do
    it "creates a room" do
      post "/api/v1/chat_rooms",
           params: { chat_room: { title: "My Room", room_kind: "group" } }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["title"]).to eq("My Room")
    end

    it "returns 400 missing params" do
      post "/api/v1/chat_rooms", params: {}.to_json, headers: json_headers(delegate)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/chat_rooms" do
    it "returns rooms for current delegate" do
      get "/api/v1/chat_rooms", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "POST /api/v1/chat_rooms/:id/join" do
    let(:room) { create(:chat_room) }

    it "joins a room" do
      post "/api/v1/chat_rooms/#{room.id}/join", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/chat_rooms/:id/leave" do
    let(:room) { create(:chat_room) }

    it "cannot leave as last admin" do
      room.chat_room_members.create!(delegate: delegate, role: :admin)
      delete "/api/v1/chat_rooms/#{room.id}/leave", headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
