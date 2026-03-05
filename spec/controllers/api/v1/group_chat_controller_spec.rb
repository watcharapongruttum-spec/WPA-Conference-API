require "rails_helper"

RSpec.describe Api::V1::GroupChatController, type: :request do
  let(:delegate) { create(:delegate) }

  describe "GET /api/v1/group_chat" do
    it "returns rooms" do
      get "/api/v1/group_chat", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("data")
    end
  end

  describe "POST /api/v1/group_chat" do
    it "creates room with 3+ members" do
      members = create_list(:delegate, 2)
      post "/api/v1/group_chat",
           params: { title: "Test", member_ids: members.map(&:id) }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:created)
    end

    it "rejects less than 3 members" do
      post "/api/v1/group_chat",
           params: { title: "Test", member_ids: [] }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects blank title" do
      members = create_list(:delegate, 2)
      post "/api/v1/group_chat",
           params: { title: "", member_ids: members.map(&:id) }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/group_chat/:id/messages" do
    let(:room) { create(:chat_room, room_kind: :group) }
    before { room.chat_room_members.create!(delegate: delegate, role: :admin) }

    it "returns messages" do
      get "/api/v1/group_chat/#{room.id}/messages", headers: json_headers(delegate)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("data")
    end
  end

  describe "POST /api/v1/group_chat/:id/messages" do
    let(:room) { create(:chat_room, room_kind: :group) }
    before { room.chat_room_members.create!(delegate: delegate, role: :admin) }

    it "sends a message" do
      post "/api/v1/group_chat/#{room.id}/messages",
           params: { content: "Hello!" }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["content"]).to eq("Hello!")
    end

    it "rejects blank content" do
      post "/api/v1/group_chat/#{room.id}/messages",
           params: { content: "" }.to_json,
           headers: json_headers(delegate)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects non-member" do
      other = create(:delegate)
      post "/api/v1/group_chat/#{room.id}/messages",
           params: { content: "Hello!" }.to_json,
           headers: json_headers(other)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
