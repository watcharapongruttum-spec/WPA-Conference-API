# app/serializers/api/v1/chat_message_serializer.rb
module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :is_deleted, :sender, :recipient,
                 :message_type, :image_url  # ✅

      attribute :created_at
      attribute :read_at
      attribute :edited_at
      attribute :deleted_at

      def is_deleted    = object.deleted_at.present?
      def created_at    = TimeFormatter.format(object.created_at)
      def read_at       = TimeFormatter.format(object.read_at)
      def edited_at     = TimeFormatter.format(object.edited_at)
      def deleted_at    = TimeFormatter.format(object.deleted_at)
      def message_type  = object.message_type   # ✅ "text" | "image"
      def image_url     = object.image_url       # ✅ nil ถ้าไม่มีรูป

      def sender
        DelegatePresenter.basic(object.sender)
      end

      def recipient
        DelegatePresenter.basic(object.recipient)
      end
    end
  end
end