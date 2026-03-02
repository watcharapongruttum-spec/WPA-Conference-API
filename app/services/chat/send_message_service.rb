# app/services/chat/send_image_service.rb
module Chat
  class SendImageService
    def self.call(sender:, recipient_id:, data_uri:)
      new(sender, recipient_id, data_uri).call
    end

    def initialize(sender, recipient_id, data_uri)
      @sender     = sender
      @recipient  = Delegate.find(recipient_id)
      @data_uri   = data_uri
    end

    def call
      create_message
      attach_image
      auto_mark_if_recipient_connected
      broadcast_new_message
      @message
    end

    private

    def create_message
      @message = ChatMessage.create!(
        sender:       @sender,
        recipient:    @recipient,
        content:      "",
        message_type: "image"  # ✅
      )
    end

    def attach_image
      Chat::ImageService.attach(message: @message, data_uri: @data_uri)
    end

    def auto_mark_if_recipient_connected
      active_room = REDIS.get("chat:active_room:#{@recipient.id}")
      return unless active_room == @sender.id.to_s

      @message.update_columns(
        read_at:      Time.current,
        delivered_at: Time.current
      )
    end

    def broadcast_new_message
      payload = {
        type:    "new_message",
        message: Api::V1::ChatMessageSerializer
                   .new(@message.reload)
                   .serializable_hash
      }
      ChatChannel.broadcast_to(@recipient, payload)
      ChatChannel.broadcast_to(@sender, payload)
    end
  end
end