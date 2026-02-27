# spec/controllers/api/v1/dashboard_controller_spec.rb
require "rails_helper"

RSpec.describe Api::V1::DashboardController, type: :controller do
  describe "GET #show" do
    let(:me)      { create(:delegate) }
    let(:other)   { create(:delegate) }
    let(:room)    { create(:chat_room, room_kind: :group) }

    before do
      request.headers["Authorization"] = "Bearer #{me.generate_jwt_token}"
      room.chat_room_members.create!(delegate: me,    role: :member)
      room.chat_room_members.create!(delegate: other, role: :member)
    end

    # -------------------------------------------------------
    # บัค #4: Group unread ต้องดูจาก MessageRead ไม่ใช่ read_at
    # -------------------------------------------------------
    context "group unread count" do
      it "counts unread group messages correctly via MessageRead" do
        # other ส่ง message — me ยังไม่ได้อ่าน
        create(:chat_message, chat_room: room, sender: other, content: "hello")

        get :show
        data = JSON.parse(response.body)

        expect(data["new_messages_count"]).to eq(1)
      end

      it "does NOT count messages me already read (via MessageRead)" do
        msg = create(:chat_message, chat_room: room, sender: other, content: "hello")

        # mark read ผ่าน MessageRead (วิธีที่ group chat ใช้จริง)
        MessageRead.mark_for(delegate: me, message_ids: [msg.id])

        get :show
        data = JSON.parse(response.body)

        expect(data["new_messages_count"]).to eq(0)
      end

      it "does NOT count my own messages as unread" do
        create(:chat_message, chat_room: room, sender: me, content: "my msg")

        get :show
        data = JSON.parse(response.body)

        expect(data["new_messages_count"]).to eq(0)
      end

      it "does NOT count deleted messages" do
        create(:chat_message, chat_room: room, sender: other,
                              content: "deleted", deleted_at: Time.current)

        get :show
        data = JSON.parse(response.body)

        expect(data["new_messages_count"]).to eq(0)
      end

      it "combines direct + group unread correctly" do
        # direct message
        create(:chat_message, sender: other, recipient: me, content: "direct")

        # group message (unread)
        create(:chat_message, chat_room: room, sender: other, content: "group")

        get :show
        data = JSON.parse(response.body)

        expect(data["new_messages_count"]).to eq(2)
      end
    end
  end
end
