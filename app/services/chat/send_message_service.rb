module Chat
  class SendMessageService
    def self.call(sender:, recipient_id:, content:)
      new(sender, recipient_id, content).call
    end

    def initialize(sender, recipient_id, content)
      @sender = sender
      @recipient = Delegate.find(recipient_id)
      @content = content
    end

    def call
      create_message
      mark_delivered_if_open
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

    def mark_delivered_if_open
      key = "chat_open:#{@recipient.id}:#{@sender.id}"

      if REDIS.get(key) == "1"
        Chat::DeliveryService.mark_one(@message)
      end
    end






    def broadcast_new_message
      payload = {
        type: 'new_message',
        message: Api::V1::ChatMessageSerializer
          .new(@message)
          .serializable_hash
      }

      ChatChannel.broadcast_to(@recipient, payload)
      ChatChannel.broadcast_to(@sender, payload)
    end
  end
end
