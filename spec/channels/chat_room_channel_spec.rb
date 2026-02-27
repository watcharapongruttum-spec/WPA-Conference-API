# spec/channels/chat_room_channel_spec.rb
require "rails_helper"

RSpec.describe ChatRoomChannel, type: :channel do
  let(:delegate1) { create(:delegate) }
  let(:delegate2) { create(:delegate) }
  let(:room) do
    r = create(:chat_room, room_kind: :direct)
    r.chat_room_members.create!(delegate: delegate1, role: :member)
    r.chat_room_members.create!(delegate: delegate2, role: :member)
    r
  end

  before do
    stub_connection current_delegate: delegate1
    subscribe(room_id: room.id)
  end

  # -------------------------------------------------------
  # บัค #1: ไม่มี dead class method self.auto_read_if_open อีกแล้ว
  # -------------------------------------------------------
  describe "class methods" do
    it "does NOT have dead self.auto_read_if_open class method" do
      expect(described_class).not_to respond_to(:auto_read_if_open)
    end
  end

  describe "#send_message" do
    it "broadcasts room_message" do
      expect do
        perform :send_message, content: "Hello"
      end.to have_broadcasted_to(room).with(
        hash_including(type: "room_message")
      )
    end

    it "auto marks as read if other user is viewing the room" do
      # simulate delegate2 เปิดห้องอยู่
      REDIS.set("chat_open:#{delegate2.id}:#{delegate1.id}", 1)

      perform :send_message, content: "Auto read test"

      msg = room.chat_messages.last
      expect(msg.read_at).not_to be_nil

      REDIS.del("chat_open:#{delegate2.id}:#{delegate1.id}")
    end

    it "does NOT auto mark as read if other user is NOT in room" do
      REDIS.del("chat_open:#{delegate2.id}:#{delegate1.id}")

      perform :send_message, content: "Not read yet"

      msg = room.chat_messages.last
      expect(msg.read_at).to be_nil
    end

    it "ignores blank content" do
      expect do
        perform :send_message, content: "   "
      end.not_to change(ChatMessage, :count)
    end
  end

  describe "#enter_room" do
    it "sets presence key in Redis" do
      perform :enter_room, {}
      key = "chat_open:#{delegate1.id}:#{delegate2.id}"
      expect(REDIS.get(key)).to eq("1")
    end

    it "marks existing messages as read" do
      msg = create(:chat_message,
                   sender: delegate2,
                   recipient: delegate1,
                   read_at: nil)

      perform :enter_room, {}

      expect(msg.reload.read_at).not_to be_nil
    end
  end

  describe "#leave_room" do
    it "removes presence key from Redis" do
      REDIS.set("chat_open:#{delegate1.id}:#{delegate2.id}", 1)

      perform :leave_room, {}

      key = "chat_open:#{delegate1.id}:#{delegate2.id}"
      expect(REDIS.get(key)).to be_nil
    end
  end

  describe "authorization" do
    it "rejects subscription if delegate is not a room member" do
      stranger = create(:delegate)
      stub_connection current_delegate: stranger

      subscribe(room_id: room.id)

      expect(subscription).to be_rejected
    end
  end
end
