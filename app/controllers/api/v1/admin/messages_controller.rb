# app/controllers/api/v1/admin/messages_controller.rb
module Api
  module V1
    module Admin
      class MessagesController < Api::V1::Admin::BaseController
        def direct
          delegate_a = params[:delegate_a_id]
          delegate_b = params[:delegate_b_id]
          page       = (params[:page] || 1).to_i
          per        = [(params[:per] || 50).to_i, 100].min

          unless delegate_a.present? && delegate_b.present?
            return render json: { error: "delegate_a_id and delegate_b_id are required" },
                          status: :unprocessable_entity
          end

          unless Delegate.exists?(delegate_a) && Delegate.exists?(delegate_b)
            return render json: { error: "Delegate not found" }, status: :not_found
          end

          scope = ChatMessage
                    .where(chat_room_id: nil)
                    .where(
                      "(sender_id = :a AND recipient_id = :b) OR
                       (sender_id = :b AND recipient_id = :a)",
                      a: delegate_a, b: delegate_b
                    )
                    .includes(:sender, :recipient)
                    .order(created_at: :desc)

          total = scope.count
          msgs  = scope.offset((page - 1) * per).limit(per)

          delegate_a_obj = Delegate.find(delegate_a)
          delegate_b_obj = Delegate.find(delegate_b)

          render json: {
            total:       total,
            page:        page,
            per:         per,
            total_pages: (total.to_f / per).ceil,
            delegate_a: {
              id:         delegate_a_obj.id,
              name:       delegate_a_obj.name,
              avatar_url: delegate_a_obj.avatar_url
            },
            delegate_b: {
              id:         delegate_b_obj.id,
              name:       delegate_b_obj.name,
              avatar_url: delegate_b_obj.avatar_url
            },
            messages: msgs.map { |m|
              {
                id:           m.id,
                content:      m.content,
                message_type: m.message_type,
                image_url:    m.image_url,
                created_at:   m.created_at&.iso8601,
                is_deleted:   m.deleted_at.present?,
                read_at:      m.read_at&.iso8601,
                sender: {
                  id:         m.sender.id,
                  name:       m.sender.name,
                  avatar_url: m.sender.avatar_url
                }
              }
            }
          }
        end
      end
    end
  end
end
