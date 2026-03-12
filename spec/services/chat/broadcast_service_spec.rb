# spec/services/chat/broadcast_service_spec.rb
require "rails_helper"

RSpec.describe Chat::BroadcastService do
  let(:sender)    { create(:delegate) }
  let(:recipient) { create(:delegate) }
  let(:room)      { create(:chat_room, room_kind: :group) }
  let(:message) do
    create(:chat_message, sender: sender, recipient: recipient, content: "hello")
  end
  let(:group_message) do
    create(:chat_message, sender: sender, chat_room: room, content: "hi group", recipient: nil)
  end

  def expect_broadcast(channel, target, type:)
    expect(channel).to have_received(:broadcast_to)
      .with(target, hash_including(type: type))
  end

  before do
    allow(ChatChannel).to      receive(:broadcast_to)
    allow(GroupChatChannel).to receive(:broadcast_to)
  end

  describe ".new_message" do
    it "broadcasts to both sender and recipient" do
      described_class.new_message(message)
      expect_broadcast(ChatChannel, sender,    type: WsEvents::CHAT_NEW_MESSAGE)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_NEW_MESSAGE)
    end
  end

  describe ".message_updated" do
    it "broadcasts message_updated to both sides" do
      described_class.message_updated(message)
      expect_broadcast(ChatChannel, sender,    type: WsEvents::CHAT_MESSAGE_UPDATED)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_MESSAGE_UPDATED)
    end

    it "includes content and edited_at" do
      message.update!(content: "edited", edited_at: Time.current)
      described_class.message_updated(message)
      expect(ChatChannel).to have_received(:broadcast_to)
        .with(sender, hash_including(content: "edited"))
    end
  end

  describe ".message_deleted" do
    it "broadcasts message_deleted to both sides" do
      described_class.message_deleted(message)
      expect_broadcast(ChatChannel, sender,    type: WsEvents::CHAT_MESSAGE_DELETED)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_MESSAGE_DELETED)
    end
  end

  describe ".message_read" do
    it "broadcasts message_read with read_at" do
      described_class.message_read(message, read_at: Time.current)
      expect(ChatChannel).to have_received(:broadcast_to)
        .with(sender, hash_including(type: WsEvents::CHAT_MESSAGE_READ, message_id: message.id))
    end
  end

  describe ".bulk_read_direct" do
    it "does nothing when message_ids is empty" do
      described_class.bulk_read_direct(message_ids: [], reader: recipient, read_at: Time.current)
      expect(ChatChannel).not_to have_received(:broadcast_to)
    end

    it "broadcasts to senders of the messages" do
      described_class.bulk_read_direct(
        message_ids: [message.id],
        reader:      recipient,
        read_at:     Time.current
      )
      expect_broadcast(ChatChannel, sender,    type: WsEvents::CHAT_BULK_READ)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_BULK_READ)
    end
  end

  describe ".typing_start / .typing_stop" do
    it "broadcasts typing_start to recipient" do
      described_class.typing_start(recipient, sender_id: sender.id)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_TYPING_START)
    end

    it "broadcasts typing_stop to recipient" do
      described_class.typing_stop(recipient, sender_id: sender.id)
      expect_broadcast(ChatChannel, recipient, type: WsEvents::CHAT_TYPING_STOP)
    end
  end

  describe ".group_new_message" do
    it "broadcasts group_new_message to room" do
      described_class.group_new_message(room, group_message)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::GROUP_NEW_MESSAGE)
    end

    it "includes room_id" do
      described_class.group_new_message(room, group_message)
      expect(GroupChatChannel).to have_received(:broadcast_to)
        .with(room, hash_including(room_id: room.id))
    end
  end

  describe ".group_message_edited" do
    it "broadcasts group_message_edited" do
      described_class.group_message_edited(room, group_message)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::GROUP_MESSAGE_EDITED)
    end
  end

  describe ".group_message_deleted" do
    it "broadcasts group_message_deleted" do
      described_class.group_message_deleted(room, group_message)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::GROUP_MESSAGE_DELETED)
    end
  end

  describe ".group_bulk_read" do
    it "does nothing when message_ids is empty" do
      described_class.group_bulk_read(room, message_ids: [], reader: sender, read_at: Time.current)
      expect(GroupChatChannel).not_to have_received(:broadcast_to)
    end

    it "broadcasts bulk_read to room" do
      described_class.group_bulk_read(
        room,
        message_ids: [group_message.id],
        reader:      sender,
        read_at:     Time.current
      )
      expect_broadcast(GroupChatChannel, room, type: WsEvents::GROUP_BULK_READ)
    end
  end

  describe ".room_member_joined / .room_member_left / .room_deleted" do
    it "broadcasts member_joined" do
      described_class.room_member_joined(room, sender)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::ROOM_MEMBER_JOINED)
    end

    it "broadcasts member_left" do
      described_class.room_member_left(room, sender.id)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::ROOM_MEMBER_LEFT)
    end

    it "broadcasts room_deleted" do
      described_class.room_deleted(room)
      expect_broadcast(GroupChatChannel, room, type: WsEvents::ROOM_DELETED)
    end
  end
end