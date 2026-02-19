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
      auto_mark_if_recipient_connected
      broadcast_new_message
      @message
    end

    private

    def create_message
      @message = ChatMessage.create!(
        sender: @sender,
        recipient: @recipient,
        content: @content
      )
    end

    def auto_mark_if_recipient_connected
      # ✅ เช็ก active_room เท่านั้น — ต้องเปิดห้องแชทกับ sender คนนี้จริงๆ
      active_room = REDIS.get("chat:active_room:#{@recipient.id}")
      return unless active_room == @sender.id.to_s

      @message.update_columns(
        read_at: Time.current,
        delivered_at: Time.current
      )
    end

    def broadcast_new_message
      payload = {
        type: 'new_message',
        message: Api::V1::ChatMessageSerializer
                   .new(@message.reload)
                   .serializable_hash
      }

      ChatChannel.broadcast_to(@recipient, payload)
      ChatChannel.broadcast_to(@sender, payload)
    end
  end
end