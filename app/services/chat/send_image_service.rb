# app/services/chat/send_image_service.rb
module Chat
  class SendImageService
    def self.call(sender:, recipient_id:, data_uri:)
      new(sender, recipient_id, data_uri).call
    end

    def initialize(sender, recipient_id, data_uri)
      @sender    = sender
      @recipient = Delegate.find(recipient_id)
      @data_uri  = data_uri
    end

    def call
      create_message
      attach_image
      mark_sender_read          # ✅
      auto_mark_if_recipient_connected
      @message
    end

    private

    def create_message
      @message = ChatMessage.create!(
        sender:       @sender,
        recipient:    @recipient,
        content:      "",
        message_type: "image"
      )
    end

    def attach_image
      Chat::ImageService.attach(message: @message, data_uri: @data_uri)
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
      Rails.logger.warn "[SendImageService] mark_sender_read failed: #{e.message}"
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
      Rails.logger.warn "[SendImageService] auto_mark failed: #{e.message}"
    end
  end
end