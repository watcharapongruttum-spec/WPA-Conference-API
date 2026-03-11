# app/services/chat/send_message_service.rb
module Chat
  class SendMessageService
    def self.call(sender:, recipient_id:, content:)
      new(sender, recipient_id, content).call
    end

    def initialize(sender, recipient_id, content)
      @sender    = sender
      @recipient = Delegate.find(recipient_id)
      @content   = content
    end

    def call
      create_message
      mark_sender_read       # ✅ sender อ่านข้อความตัวเองทันที
      auto_mark_if_recipient_connected
      @message
    end

    private

    def create_message
      @message = ChatMessage.create!(
        sender:    @sender,
        recipient: @recipient,
        content:   @content
      )
    end

    # ✅ sender ส่งแล้วถือว่าอ่านแล้วเสมอ
    def mark_sender_read
      now = Time.current
      MessageRead.upsert(
        {
          chat_message_id: @message.id,
          delegate_id:     @sender.id,
          read_at:         now,
          created_at:      now,
          updated_at:      now
        },
        unique_by: %i[chat_message_id delegate_id]
      )
    rescue => e
      Rails.logger.warn "[SendMessageService] mark_sender_read failed: #{e.message}"
    end

    def auto_mark_if_recipient_connected
      active_room = REDIS.get("chat:active_room:#{@recipient.id}")
      return unless active_room == @sender.id.to_s

      now = Time.current
      @message.update_columns(read_at: now, delivered_at: now)

      # ✅ insert MessageRead สำหรับ recipient ด้วย
      MessageRead.upsert(
        {
          chat_message_id: @message.id,
          delegate_id:     @recipient.id,
          read_at:         now,
          created_at:      now,
          updated_at:      now
        },
        unique_by: %i[chat_message_id delegate_id]
      )
    rescue => e
      Rails.logger.warn "[SendMessageService] auto_mark failed: #{e.message}"
    end
  end
end