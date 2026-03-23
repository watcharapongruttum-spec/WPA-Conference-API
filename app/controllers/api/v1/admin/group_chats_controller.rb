# app/controllers/api/v1/admin/group_chats_controller.rb
module Api
  module V1
    module Admin
      class GroupChatsController < Api::V1::Admin::BaseController

        
        def index
          rooms = ChatRoom
                    .where(room_kind: :group, deleted_at: nil)
                    .includes(:chat_room_members)
                    .order(created_at: :desc)

          render json: {
            total: rooms.size,
            rooms: rooms.map { |r| room_json(r) }
          }
        end

        def show
          room = ChatRoom.includes(chat_room_members: :delegate).find(params[:id])
          render json: room_json(room, detail: true)
        end








        def destroy
          room = ChatRoom.find(params[:id])

          ActiveRecord::Base.transaction do
            room.update!(deleted_at: Time.current)
            Chat::Group::BroadcastService.room_deleted(room)
          end

          render json: { success: true, deleted_id: room.id }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Room not found" }, status: :not_found
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        end

        def messages
          room = ChatRoom.find(params[:id])
          page = (params[:page] || 1).to_i
          per  = [(params[:per] || 50).to_i, 100].min

          msgs = room.chat_messages
                      .where(deleted_at: nil)
                      .includes(:sender)
                      .order(created_at: :desc)
                      .offset((page - 1) * per)
                      .limit(per)

          total = room.chat_messages.where(deleted_at: nil).count

          render json: {
            room_id:     room.id,
            room_title:  room.title,
            total:       total,
            page:        page,
            per:         per,
            total_pages: (total.to_f / per).ceil,
            messages:    msgs.map { |m| message_json(m) }
          }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Room not found" }, status: :not_found
        end














        

        private

        def room_json(room, detail: false)
          data = {
            id:           room.id,
            title:        room.title,
            room_kind:    room.room_kind,
            member_count: room.chat_room_members.size,
            created_at:   room.created_at&.iso8601
          }

          if detail
            data[:members] = room.chat_room_members.map { |m|
              {
                id:         m.delegate&.id,
                name:       m.delegate&.name,
                role:       m.role,
                avatar_url: m.delegate&.avatar_url
              }
            }
          end

          data
        end





        def message_json(m)
          {
            id:           m.id,
            content:      m.content,
            message_type: m.message_type,
            image_url:    m.image_url,
            created_at:   m.created_at&.iso8601,
            edited_at:    m.edited_at&.iso8601,
            sender: {
              id:         m.sender.id,
              name:       m.sender.name,
              avatar_url: m.sender.avatar_url
            }
          }
        end







      end
    end
  end
end