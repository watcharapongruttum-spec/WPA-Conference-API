# spec/services/chat/read_service_spec.rb
require "rails_helper"

RSpec.describe Chat::ReadService do
  let(:me)    { create(:delegate) }
  let(:other) { create(:delegate) }

  # -------------------------------------------------------
  # บัค #5: read_all group chat ต้องใช้ MessageRead
  # -------------------------------------------------------
  describe ".read_all" do
    context "direct messages" do
      it "marks direct messages as read via read_at" do
        msg = create(:chat_message, sender: other, recipient: me, read_at: nil)

        Chat::ReadService.read_all(me)

        expect(msg.reload.read_at).not_to be_nil
      end
    end

    context "group messages" do
      let(:room) { create(:chat_room, room_kind: :group) }

      before do
        room.chat_room_members.create!(delegate: me,    role: :member)
        room.chat_room_members.create!(delegate: other, role: :member)
      end

      it "marks group messages as read via MessageRead table" do
        msg = create(:chat_message, chat_room: room, sender: other, content: "hi")

        expect(MessageRead.where(chat_message_id: msg.id, delegate_id: me.id)).to be_empty

        Chat::ReadService.read_all(me)

        expect(MessageRead.where(chat_message_id: msg.id, delegate_id: me.id)).to exist
      end

      it "does NOT create MessageRead for my own messages" do
        msg = create(:chat_message, chat_room: room, sender: me, content: "my msg")

        Chat::ReadService.read_all(me)

        # sender ควรถูก mark จาก GroupChatChannel#speak ไม่ใช่ read_all
        # read_all ไม่ควร double-process message ของตัวเอง
        expect(MessageRead.where(
          chat_message_id: msg.id,
          delegate_id: me.id
        ).count).to eq(0)
      end

      it "does not re-mark already read messages" do
        msg = create(:chat_message, chat_room: room, sender: other, content: "hi")
        MessageRead.mark_for(delegate: me, message_ids: [msg.id])
        original_read_at = MessageRead.find_by(chat_message_id: msg.id, delegate_id: me.id).read_at

        Chat::ReadService.read_all(me)

        current_read_at = MessageRead.find_by(chat_message_id: msg.id, delegate_id: me.id).read_at
        expect(current_read_at).to be_within(1.second).of(original_read_at)
      end

      it "clears dashboard cache after read" do
        cache_key = "dashboard:#{me.id}:v1"
        Rails.cache.write(cache_key, { new_messages_count: 5 })

        Chat::ReadService.read_all(me)

        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it "skips deleted rooms" do
        deleted_room = create(:chat_room, room_kind: :group, deleted_at: Time.current)
        deleted_room.chat_room_members.create!(delegate: me, role: :member)
        msg = create(:chat_message, chat_room: deleted_room, sender: other, content: "hi")

        Chat::ReadService.read_all(me)

        expect(MessageRead.where(chat_message_id: msg.id, delegate_id: me.id)).not_to exist
      end
    end
  end
end
