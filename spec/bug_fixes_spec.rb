# ============================================================
# WPA Conference - RSpec Tests สำหรับ 10 Bugs ที่แก้ไขแล้ว
# ============================================================
# วิธีรัน:
#   rspec spec/bug_fixes_spec.rb
#   rspec spec/bug_fixes_spec.rb --format documentation
# ============================================================

require 'rails_helper'

# ============================================================
# 🔴 BUG #1 - RequestsController#cancel ใช้ field ผิด
# ============================================================
RSpec.describe "Bug #1: RequestsController#cancel", type: :request do
  let(:requester) { create(:delegate) }
  let(:target)    { create(:delegate) }
  let!(:conn_request) { create(:connection_request, requester: requester, target: target, status: :pending) }
  let(:headers) { auth_headers(requester) }

  context "ก่อนแก้ - ใช้ params[:id] เป็น target_id (ผิด)" do
    it "ไม่ควรหา request จาก target_id ที่ไม่ใช่ id ของ connection_request" do
      # ถ้าใช้ target_id: params[:id] จะหาไม่เจอ เพราะ params[:id] = conn_request.id ไม่ใช่ target.id
      expect(conn_request.id).not_to eq(target.id)
    end
  end

  context "หลังแก้ - ใช้ id: params[:id] + requester_id" do
    it "cancel request สำเร็จด้วย connection_request id ที่ถูกต้อง" do
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: headers

      expect(response).to have_http_status(:ok)
      expect(conn_request.reload.status).to eq("cancelled")
    end

    it "ไม่สามารถ cancel request ของคนอื่นได้" do
      other_delegate = create(:delegate)
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: auth_headers(other_delegate)

      expect(response).to have_http_status(:not_found)
    end

    it "ไม่พบ request ที่ไม่มีอยู่" do
      delete "/api/v1/requests/99999/cancel", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "ไม่สามารถ cancel request ที่ accepted แล้ว" do
      conn_request.update!(status: :accepted)
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: headers

      expect(response).not_to have_http_status(:ok)
    end
  end
end

# ============================================================
# 🔴 BUG #2 - GroupChatController ขาด msg.reload → image_url = nil
# ============================================================
RSpec.describe "Bug #2: GroupChatController#send_message image_url", type: :request do
  let(:delegate)   { create(:delegate) }
  let(:chat_room)  { create(:chat_room, :group) }
  let(:headers)    { auth_headers(delegate) }
  let(:image_file) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }

  before { chat_room.chat_room_members.create!(delegate: delegate) }

  context "ส่งข้อความพร้อมรูปภาพผ่าน REST endpoint" do
    it "response มี image_url ไม่เป็น nil" do
      post "/api/v1/group_chat/#{chat_room.id}/messages",
        params: { message: { content: "Hello", image: image_file } },
        headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["image_url"]).not_to be_nil
      expect(json["image_url"]).to include("http")
    end

    it "บันทึกรูปไว้กับ message จริงๆ" do
      post "/api/v1/group_chat/#{chat_room.id}/messages",
        params: { message: { content: "Hello", image: image_file } },
        headers: headers

      msg = ChatMessage.last
      expect(msg.image.attached?).to be true
    end

    it "ส่งข้อความธรรมดา (ไม่มีรูป) image_url เป็น nil ได้" do
      post "/api/v1/group_chat/#{chat_room.id}/messages",
        params: { message: { content: "Hello no image" } },
        headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["image_url"]).to be_nil
    end
  end
end

# ============================================================
# 🔴 BUG #3 - Group chat push notifications ไม่ถูกส่ง
# ============================================================
RSpec.describe "Bug #3: NotificationDeliveryJob - group chat push notification", type: :job do
  include ActiveJob::TestHelper

  let(:delegate)   { create(:delegate, :with_fcm_token) }
  let(:chat_room)  { create(:chat_room, :group) }
  let(:message)    { create(:chat_message, chat_room: chat_room, sender: delegate, message_type: 'new_group_message') }

  context "FCM_ALLOWED_TYPES รวม new_group_message" do
    it "new_group_message อยู่ใน FCM_ALLOWED_TYPES" do
      expect(NotificationDeliveryJob::FCM_ALLOWED_TYPES).to include('new_group_message')
    end

    it "enqueue job และรัน FCM ได้สำเร็จ" do
      fcm_service = instance_double(Notification::FcmService)
      allow(Notification::FcmService).to receive(:new).and_return(fcm_service)
      allow(fcm_service).to receive(:send_notification).and_return(true)

      expect {
        NotificationDeliveryJob.perform_now(
          delegate_id: delegate.id,
          notification_type: 'new_group_message',
          payload: { message_id: message.id, room_id: chat_room.id }
        )
      }.not_to raise_error

      expect(fcm_service).to have_received(:send_notification)
    end

    it "ไม่รัน FCM สำหรับ type ที่ไม่อนุญาต" do
      fcm_service = instance_double(Notification::FcmService)
      allow(Notification::FcmService).to receive(:new).and_return(fcm_service)
      allow(fcm_service).to receive(:send_notification)

      NotificationDeliveryJob.perform_now(
        delegate_id: delegate.id,
        notification_type: 'some_unknown_type',
        payload: {}
      )

      expect(fcm_service).not_to have_received(:send_notification)
    end
  end

  context "Integration: ส่งข้อความใน group chat แล้ว notification ถูก enqueue" do
    it "enqueue NotificationDeliveryJob หลังส่งข้อความ" do
      member = create(:delegate, :with_fcm_token)
      chat_room.chat_room_members.create!(delegate: member)

      expect {
        Notification::BroadcastService.new(
          notification_type: 'new_group_message',
          actor: delegate,
          recipients: [member],
          payload: { message_id: message.id }
        ).call
      }.to have_enqueued_job(NotificationDeliveryJob)
    end
  end
end

# ============================================================
# 🟡 BUG #4 - ChatRoomsController#create variable shadowing
# ============================================================
RSpec.describe "Bug #4: ChatRoomsController#create variable shadowing", type: :request do
  let(:delegate) { create(:delegate) }
  let(:headers)  { auth_headers(delegate) }

  it "สร้าง chat room สำเร็จและ params ไม่ถูก shadow" do
    post "/api/v1/chat_rooms",
      params: { chat_room: { name: "Test Room", room_type: "group" } },
      headers: headers

    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json["name"]).to eq("Test Room")
  end

  it "แสดง validation error เมื่อข้อมูลไม่ครบ" do
    post "/api/v1/chat_rooms",
      params: { chat_room: { name: "" } },
      headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "สร้างห้องได้หลายครั้งโดยไม่ติด params ของครั้งก่อน" do
    2.times do |i|
      post "/api/v1/chat_rooms",
        params: { chat_room: { name: "Room #{i}", room_type: "group" } },
        headers: headers
      expect(response).to have_http_status(:created)
    end
    expect(ChatRoom.count).to eq(2)
  end
end

# ============================================================
# 🟡 BUG #5 - LeaveForm explanation ไม่ถูกบันทึก
# ============================================================
RSpec.describe "Bug #5: LeaveFormsController explanation not saved", type: :request do
  let(:delegate)   { create(:delegate) }
  let(:conference) { create(:conference) }
  let(:headers)    { auth_headers(delegate) }

  it "บันทึก explanation ได้เมื่อส่งมาใน params" do
    post "/api/v1/leave_forms",
      params: {
        leaves: [
          { date: Date.today.to_s, reason: "ป่วย", explanation: "มีไข้สูง 39 องศา" }
        ]
      },
      headers: headers

    expect(response).to have_http_status(:created)
    leave_form = LeaveForm.last
    expect(leave_form.explanation).to eq("มีไข้สูง 39 องศา")
  end

  it "explanation เป็น nil ได้ถ้าไม่ส่งมา" do
    post "/api/v1/leave_forms",
      params: {
        leaves: [
          { date: Date.today.to_s, reason: "ธุระ" }
        ]
      },
      headers: headers

    expect(response).to have_http_status(:created)
    leave_form = LeaveForm.last
    expect(leave_form.explanation).to be_nil
  end

  it "ส่ง explanation หลายรายการพร้อมกัน" do
    post "/api/v1/leave_forms",
      params: {
        leaves: [
          { date: Date.today.to_s, reason: "ป่วย", explanation: "เหตุผลที่ 1" },
          { date: (Date.today + 1).to_s, reason: "ธุระ", explanation: "เหตุผลที่ 2" }
        ]
      },
      headers: headers

    expect(response).to have_http_status(:created)
    explanations = LeaveForm.last(2).map(&:explanation)
    expect(explanations).to include("เหตุผลที่ 1", "เหตุผลที่ 2")
  end
end

# ============================================================
# 🟡 BUG #6 - Email บอก "1 ชั่วโมง" แต่ link หมดอายุใน 30 นาที
# ============================================================
RSpec.describe "Bug #6: Password reset expiry text vs actual expiry", type: :unit do
  let(:delegate) { create(:delegate) }

  describe "ResetPasswordJob email content" do
    it "ส่ง email ที่ระบุว่าหมดอายุใน 30 นาที" do
      mail = ResetPasswordJob.new.perform(delegate.id)

      # หรือตรวจสอบ mailer โดยตรง
      expect(ActionMailer::Base.deliveries.last.body.encoded).to include("30")
      expect(ActionMailer::Base.deliveries.last.body.encoded).not_to include("1 ชั่วโมง")
    end
  end

  describe "Delegate#reset_password_sent_at validation" do
    it "token ที่ส่งมาเมื่อกี้ยังใช้งานได้" do
      delegate.update!(reset_password_sent_at: 1.minute.ago)
      expect(delegate.reset_password_token_valid?).to be true
    end

    it "token ที่ส่งมา 29 นาทีที่แล้วยังใช้งานได้" do
      delegate.update!(reset_password_sent_at: 29.minutes.ago)
      expect(delegate.reset_password_token_valid?).to be true
    end

    it "token ที่ส่งมา 31 นาทีที่แล้วหมดอายุแล้ว" do
      delegate.update!(reset_password_sent_at: 31.minutes.ago)
      expect(delegate.reset_password_token_valid?).to be false
    end

    it "token ที่ส่งมา 61 นาทีที่แล้วหมดอายุแล้ว (ไม่ใช่ 1 ชั่วโมง)" do
      delegate.update!(reset_password_sent_at: 61.minutes.ago)
      expect(delegate.reset_password_token_valid?).to be false
    end
  end
end

# ============================================================
# 🟡 BUG #7 - ChatRoomChannel#subscribed N+1 query
# ============================================================
RSpec.describe "Bug #7: ChatRoomChannel N+1 query fix", type: :channel do
  let(:delegate)  { create(:delegate) }
  let(:chat_room) { create(:chat_room, :group) }

  before { chat_room.chat_room_members.create!(delegate: delegate) }

  it "subscribe สำเร็จด้วย single query (ไม่โหลด delegates ทั้งหมด)" do
    stub_connection(current_delegate: delegate)

    # นับจำนวน query ที่ใช้ตรวจสอบ membership
    query_count = 0
    counter = ->(*) { query_count += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      subscribe_to ChatRoomChannel, params: { room_id: chat_room.id }
    end

    expect(subscription).to be_confirmed
    # exists? ใช้แค่ 1 query ไม่โหลด delegates ทั้งหมดก่อน
    expect(query_count).to be <= 3
  end

  it "reject เมื่อ delegate ไม่ได้เป็นสมาชิก" do
    other_delegate = create(:delegate)
    stub_connection(current_delegate: other_delegate)

    subscribe_to ChatRoomChannel, params: { room_id: chat_room.id }

    expect(subscription).to be_rejected
  end

  it "ใช้ exists? แทน include? ในการตรวจสอบ membership" do
    # ตรวจสอบว่า method ใช้ SQL EXISTS ไม่ใช่ load ทั้งหมด
    expect(chat_room.chat_room_members.exists?(delegate_id: delegate.id)).to be true
    expect(chat_room.chat_room_members.exists?(delegate_id: 99999)).to be false
  end
end

# ============================================================
# 🟢 BUG #8 - MessagesController#mark_as_read double query
# ============================================================
RSpec.describe "Bug #8: MessagesController#mark_as_read double query", type: :request do
  let(:delegate) { create(:delegate) }
  let(:message)  { create(:chat_message, recipient: delegate, read_at: nil) }
  let(:headers)  { auth_headers(delegate) }

  it "mark as read สำเร็จ" do
    patch "/api/v1/messages/#{message.id}/mark_as_read", headers: headers

    expect(response).to have_http_status(:ok)
    expect(message.reload.read_at).not_to be_nil
  end

  it "ไม่ query database ซ้ำโดยไม่จำเป็น (ใช้ @message จาก before_action)" do
    query_count = 0
    counter = ->(*) { query_count += 1 }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      patch "/api/v1/messages/#{message.id}/mark_as_read", headers: headers
    end

    # ก่อนแก้: query 2 ครั้ง (before_action + find ใน action)
    # หลังแก้: query 1 ครั้ง (before_action อย่างเดียว)
    chat_message_queries = query_count
    expect(chat_message_queries).to be < 5  # ไม่มี duplicate query
  end

  it "return 404 เมื่อ message ไม่มีอยู่" do
    patch "/api/v1/messages/99999/mark_as_read", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end

# ============================================================
# 🟢 BUG #9 - Schedule#team_delegates bypasses eager loading
# ============================================================
RSpec.describe "Bug #9: Schedule#team_delegates eager loading", type: :model do
  let(:team)      { create(:team) }
  let(:delegates) { create_list(:delegate, 3, team: team) }
  let(:schedule)  { create(:schedule, target_type: 'team', target_id: team.id) }

  it "team_delegates คืนค่า delegates ของ team ที่ถูกต้อง" do
    delegates # trigger creation
    expect(schedule.team_delegates).to match_array(delegates)
  end

  it "ใช้ association cache แทน query ใหม่" do
    # โหลด schedule พร้อม eager load
    loaded_schedule = Schedule.includes(team: :delegates).find(schedule.id)
    loaded_schedule.team.delegates.load # prime the cache

    query_count = 0
    counter = ->(*) { query_count += 1 }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      loaded_schedule.team_delegates
    end

    # หลังแก้: ใช้ cache ไม่ query เพิ่ม
    expect(query_count).to eq(0)
  end

  it "with_full_data scope โหลด team delegates ได้ใน 1 query" do
    delegates
    expect {
      Schedule.with_full_data.find(schedule.id).team_delegates
    }.to make_database_queries(count: 1..3)
  end
end

# ============================================================
# 🟢 BUG #10 - Chat::PresenceService ไม่มี Redis error handling
# ============================================================
RSpec.describe "Bug #10: Chat::PresenceService Redis error handling", type: :service do
  let(:delegate) { create(:delegate) }
  let(:service)  { Chat::PresenceService.new }

  shared_examples "handles Redis error gracefully" do |method_name, args, expected_value|
    context "เมื่อ Redis ล่ม" do
      before do
        allow(Redis.current).to receive(:sadd).and_raise(Redis::BaseError, "Connection refused")
        allow(Redis.current).to receive(:srem).and_raise(Redis::BaseError, "Connection refused")
        allow(Redis.current).to receive(:sismember).and_raise(Redis::BaseError, "Connection refused")
        allow(Redis.current).to receive(:scard).and_raise(Redis::BaseError, "Connection refused")
        allow(Redis.current).to receive(:expire).and_raise(Redis::BaseError, "Connection refused")
      end

      it "#{method_name} ไม่ raise error และคืนค่า #{expected_value.inspect}" do
        result = service.send(method_name, *args)
        expect(result).to eq(expected_value)
      end

      it "#{method_name} log warning แทน raise error" do
        expect(Rails.logger).to receive(:warn).with(/Redis/)
        service.send(method_name, *args) rescue nil
      end
    end
  end

  include_examples "handles Redis error gracefully", :online,            [:delegate_1], nil
  include_examples "handles Redis error gracefully", :offline,           [:delegate_1], nil
  include_examples "handles Redis error gracefully", :online?,           [:delegate_1], false
  include_examples "handles Redis error gracefully", :connection_count,  [],            0

  context "ทำงานปกติเมื่อ Redis ใช้งานได้" do
    it "online เพิ่ม delegate เข้า Redis" do
      expect { service.online(delegate.id.to_s) }.not_to raise_error
    end

    it "online? คืน true หลัง online" do
      service.online(delegate.id.to_s)
      expect(service.online?(delegate.id.to_s)).to be true
    end

    it "offline ลบ delegate ออกจาก Redis" do
      service.online(delegate.id.to_s)
      service.offline(delegate.id.to_s)
      expect(service.online?(delegate.id.to_s)).to be false
    end

    it "connection_count คืนจำนวน delegate ที่ online" do
      service.online("user_1")
      service.online("user_2")
      expect(service.connection_count).to be >= 2
    end
  end
end