# spec/channels/group_chat_channel_spec.rb
require 'rails_helper'

RSpec.describe GroupChatChannel, type: :channel do

  let(:delegate1) { create(:delegate) }
  let(:delegate2) { create(:delegate) }
  let(:delegate3) { create(:delegate) }
  let(:room)      { create(:chat_room, room_kind: :group) }

  before do
    room.chat_room_members.create!(delegate: delegate1, role: :admin)
    room.chat_room_members.create!(delegate: delegate2, role: :member)
    room.chat_room_members.create!(delegate: delegate3, role: :member)

    stub_connection current_delegate: delegate1
    subscribe(room_id: room.id)
  end

  describe "#speak — notify_group_members loop" do

    it "continues notifying other members even if one fails" do
      call_count = 0

      allow(Notification).to receive(:create!) do |**args|
        call_count += 1
        raise "DB error" if args[:delegate] == delegate2
        build_stubbed(:notification)
      end

      expect {
        perform :speak, content: "Hello everyone"
      }.not_to raise_error

      expect(call_count).to eq(2)
    end

    # ✅ FIX: ใช้ expect { }.to have_broadcasted_to แทน expect(transmissions)
    it "broadcasts message to room regardless of notification errors" do
      allow(Notification).to receive(:create!).and_raise("fail")

      expect {
        perform :speak, content: "Test message"
      }.to have_broadcasted_to(room).with(
        hash_including("type" => "group_message")
      )
    end

  end

  describe "#enter_room" do
    it "marks unread messages as read via MessageRead" do
      msg = create(:chat_message, chat_room: room, sender: delegate2, content: "hi")

      perform :enter_room, {}

      expect(MessageRead.where(
        chat_message_id: msg.id,
        delegate_id: delegate1.id
      )).to exist
    end

    it "broadcasts bulk_read to room" do
      create(:chat_message, chat_room: room, sender: delegate2, content: "hi")

      expect {
        perform :enter_room, {}
      }.to have_broadcasted_to(room).with(
        hash_including("type" => "bulk_read")
      )
    end
  end

end