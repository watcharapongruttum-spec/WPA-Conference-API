module Chat
  class DeleteMessageService
    def self.call(message:)
      new(message).call
    end

    def initialize(message)
      @message = message
    end

    def call
      delete_message
      broadcast
    end

    private

    def delete_message
      @message.update!(deleted_at: Time.current)
    end

    def broadcast
      payload = {
        type: "message_deleted",
        message_id: @message.id
      }

      ChatChannel.broadcast_to(@message.recipient, payload)
      ChatChannel.broadcast_to(@message.sender, payload)
    end
  end
end
