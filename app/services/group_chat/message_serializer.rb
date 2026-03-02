# app/services/group_chat/message_serializer.rb
#
# Single source of truth สำหรับ serialize group chat message
# ใช้ทั้งใน GroupChatChannel และ GroupChatController
#
module GroupChat
  class MessageSerializer
    def self.call(message:, sender:)
      new(message, sender).call
    end

    def initialize(message, sender)
      @message = message
      @sender  = sender
    end

    def call
      {
        id:         @message.id,
        content:    @message.deleted_at? ? nil : @message.content,
        created_at: TimeFormatter.format(@message.created_at),
        edited_at:  TimeFormatter.format(@message.edited_at),
        deleted_at: TimeFormatter.format(@message.deleted_at),
        is_deleted: @message.deleted_at?,
        is_edited:  @message.edited_at?,
        sender:     DelegatePresenter.basic(@sender),   # ✅
        readers:    readers_for(@message)
      }
    end

    private

    def readers_for(message)
      MessageRead
        .includes(:delegate)
        .where(chat_message_id: message.id)
        .where.not(delegate_id: message.sender_id)
        .map do |mr|
          DelegatePresenter.minimal(mr.delegate)        # ✅
            .merge(read_at: TimeFormatter.format(mr.read_at))
        end
    end
  end
end