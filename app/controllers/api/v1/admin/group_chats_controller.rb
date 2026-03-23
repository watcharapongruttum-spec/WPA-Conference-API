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
      end
    end
  end
end