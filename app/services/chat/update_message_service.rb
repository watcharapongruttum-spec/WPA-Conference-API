module Chat
  class UpdateMessageService
    def self.call(message:, content:)
      new(message, content).call
    end

    def initialize(message, content)
      @message = message
      @content = content
    end

    def call
      update_message
      broadcast
    end

    private

    def update_message
      @message.update!(
        content: @content,
        edited_at: Time.current
      )
    end

    def broadcast
      payload = {
        type: "message_updated",
        message_id: @message.id,
        content: @message.content,
        edited_at: @message.edited_at
      }

      ChatChannel.broadcast_to(@message.recipient, payload)
      ChatChannel.broadcast_to(@message.sender, payload)
    end
  end
end
