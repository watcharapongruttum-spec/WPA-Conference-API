require "rails_helper"

RSpec.describe Api::V1::MessagesController, type: :request do
  let(:delegate) { create(:delegate) }
  let(:other)    { create(:delegate) }

  describe "GET /api/v1/messages/rooms" do
    it "returns direct message rooms" do
      get "/api/v1/messages/rooms", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    it "returns 401 without token" do
      get "/api/v1/messages/rooms"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/messages" do
    it "returns messages list" do
      get "/api/v1/messages", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "GET /api/v1/messages/conversation" do
    it "returns conversation with other delegate" do
      get "/api/v1/messages/conversation/#{other.id}",
          headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/messages" do
    it "sends a direct message" do
      post "/api/v1/messages",
           params: { recipient_id: other.id, content: "Hello!" }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:created)
    end

    it "rejects blank content" do
      post "/api/v1/messages",
           params: { recipient_id: other.id, content: "" }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/messages/:id/mark_as_read" do
    let(:msg) do
      ChatMessage.create!(
        sender: other,
        recipient: delegate,
        content: "Hi",
        message_type: "text"
      )
    end

    it "marks message as read" do
      patch "/api/v1/messages/#{msg.id}/mark_as_read",
            headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
    end

    it "rejects marking other's message" do
      patch "/api/v1/messages/#{msg.id}/mark_as_read",
            headers: json_headers(other)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/messages/unread_count" do
    it "returns unread count" do
      get "/api/v1/messages/unread_count", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("unread_count")
    end
  end
end
