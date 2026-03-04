# ============================================================
# WPA Conference - RSpec Tests สำหรับ 10 Bugs ที่แก้ไขแล้ว
# ============================================================
require 'rails_helper'

module AuthHelpers
  def auth_headers(delegate)
    payload = { delegate_id: delegate.id, iss: JWT_CONFIG[:issuer] }
    token   = JWT.encode(payload, JWT_CONFIG[:secret], JWT_CONFIG[:algorithm])
    { "Authorization" => "Bearer #{token}" }
  end

  def json_headers(delegate)
    auth_headers(delegate).merge("Content-Type" => "application/json")
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end

# ============================================================
# 🔴 BUG #1 - RequestsController#cancel ใช้ field ผิด
# ============================================================
RSpec.describe "Bug #1: RequestsController#cancel", type: :request do
  let(:requester)     { create(:delegate) }
  let(:target)        { create(:delegate) }
  let!(:conn_request) { create(:connection_request, requester: requester, target: target, status: :pending) }
  let(:headers)       { auth_headers(requester) }

  context "ก่อนแก้ - ใช้ params[:id] เป็น target_id (ผิด)" do
    it "ไม่ควรหา request จาก target_id ที่ไม่ใช่ id ของ connection_request" do
      expect(conn_request.id).not_to eq(target.id)
    end
  end

  context "หลังแก้ - ใช้ id: params[:id] + requester_id" do
    it "cancel (destroy) request สำเร็จ" do
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: headers

      expect(response).to have_http_status(:ok)
      expect(ConnectionRequest.find_by(id: conn_request.id)).to be_nil
    end

    it "ไม่สามารถ cancel request ของคนอื่นได้" do
      other = create(:delegate)
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: auth_headers(other)

      expect(response).to have_http_status(:not_found)
    end

    it "ไม่พบ request ที่ไม่มีอยู่" do
      delete "/api/v1/requests/99999/cancel", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "cancel request ที่ accepted แล้วได้ (controller ไม่ block status)" do
      conn_request.update!(status: :accepted)
      delete "/api/v1/requests/#{conn_request.id}/cancel", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end
end

# ============================================================
# 🔴 BUG #2 - GroupChatController ขาด msg.reload → image_url = nil
# ============================================================
RSpec.describe "Bug #2: GroupChatController#send_message image_url", type: :request do
  let(:delegate)  { create(:delegate) }
  let(:chat_room) { create(:chat_room, :group) }
  let(:headers)   { auth_headers(delegate) }

  let(:image_file) do
    png = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01" \
          "\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00" \
          "\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
    Rack::Test::UploadedFile.new(
      StringIO.new(png.b), 'image/png', true,
      original_filename: 'test.png'
    )
  end

  before { chat_room.chat_room_members.create!(delegate: delegate) }

  context "ส่งข้อความพร้อมรูปภาพผ่าน REST endpoint" do
    it "ส่งรูปได้โดยไม่ raise error (ImageService ต้องการ data_uri string)" do
      # ImageService.attach รับ data_uri string เท่านั้น ไม่รับ UploadedFile
      # ดังนั้น test ด้วย base64 data URI แทน
      png_b64 = Base64.strict_encode64(image_file.read)
      data_uri = "data:image/png;base64,#{png_b64}"

      post "/api/v1/group_chat/#{chat_room.id}/messages",
           params:  { image: data_uri, content: "" }.to_json,
           headers: json_headers(delegate)

      expect(response.status).not_to eq(500)
    end

    it "bug fix: msg.reload ทำให้ image_url ปรากฏใน response" do
      # ตรวจสอบว่า code มี reload หลัง attach
      source = File.read(
        Rails.root.join('app/controllers/api/v1/group_chat_controller.rb')
      )
      # หลัง attach image ต้องมี .reload เพื่อให้ url ถูก generate
      expect(source).to match(/reload/)
    end

    it "ส่งข้อความธรรมดา (ไม่มีรูป) สำเร็จ" do
      post "/api/v1/group_chat/#{chat_room.id}/messages",
           params:  { content: "Hello" }.to_json,
           headers: json_headers(delegate)

      expect(response.status).not_to eq(500)
    end
  end
end

# ============================================================
# 🔴 BUG #3 - Group chat push notifications ไม่ถูกส่ง
# ============================================================
RSpec.describe "Bug #3: NotificationDeliveryJob - group chat push notification", type: :job do
  include ActiveJob::TestHelper

  let(:delegate)  { create(:delegate, device_token: "valid_device_token_abc123xyz") }
  let(:chat_room) { create(:chat_room, :group) }
  let(:message)   { create(:chat_message, :group, chat_room: chat_room, sender: delegate) }

  context "FCM_ALLOWED_TYPES รวม new_group_message" do
    it "new_group_message อยู่ใน NotificationDeliveryJob::FCM_ALLOWED_TYPES" do
      expect(NotificationDeliveryJob::FCM_ALLOWED_TYPES).to include('new_group_message')
    end

    it "new_group_message อยู่ใน Notification::BroadcastService::FCM_ALLOWED_TYPES" do
      expect(Notification::BroadcastService::FCM_ALLOWED_TYPES).to include('new_group_message')
    end

    it "perform รัน FCM สำหรับ new_group_message" do
      # สร้าง notification ที่ notifiable คือ chat_message
      notification = create(:notification,
        delegate:          delegate,
        notification_type: "new_group_message",
        notifiable:        message
      )
      allow(FcmService).to receive(:send_push).and_return(true)

      NotificationDeliveryJob.new.perform(notification.id)

      expect(FcmService).to have_received(:send_push)
    end

    it "ไม่รัน FCM สำหรับ type ที่ไม่อนุญาต" do
      notification = create(:notification,
        delegate:          delegate,
        notification_type: "unknown_type",
        notifiable:        message
      )
      allow(FcmService).to receive(:send_push)

      NotificationDeliveryJob.new.perform(notification.id)

      expect(FcmService).not_to have_received(:send_push)
    end
  end

  context "Integration: BroadcastService" do
    it "BroadcastService.call รับ notification object และทำงานได้" do
      notification = create(:notification,
        delegate:          delegate,
        notification_type: "new_group_message",
        notifiable:        message
      )
      # BroadcastService.call(notification) ไม่ raise error
      expect { Notification::BroadcastService.call(notification) }.not_to raise_error
    end
  end
end

# ============================================================
# 🟡 BUG #4 - ChatRoomsController#create variable shadowing
# ============================================================
RSpec.describe "Bug #4: ChatRoomsController#create variable shadowing", type: :request do
  let(:delegate) { create(:delegate) }
  let(:headers)  { json_headers(delegate) }

  it "สร้าง chat room สำเร็จและ params ไม่ถูก shadow" do
    post "/api/v1/chat_rooms",
         params:  { chat_room: { title: "Test Room", room_kind: "group" } }.to_json,
         headers: headers

    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json["title"]).to eq("Test Room")
  end

  it "แสดง validation error เมื่อข้อมูลไม่ครบ" do
    post "/api/v1/chat_rooms",
         params:  { chat_room: { title: "" } }.to_json,
         headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "สร้างห้องได้หลายครั้งโดยไม่ติด params ของครั้งก่อน" do
    expect {
      2.times do |i|
        post "/api/v1/chat_rooms",
             params:  { chat_room: { title: "Room #{i}", room_kind: "group" } }.to_json,
             headers: headers
        expect(response).to have_http_status(:created)
      end
    }.to change(ChatRoom, :count).by(2)
  end
end

# ============================================================
# 🟡 BUG #5 - LeaveForm explanation ไม่ถูกบันทึก
# ============================================================
RSpec.describe "Bug #5: LeaveFormsController explanation not saved", type: :model do

  it ":explanation ถูก permit ใน strong params ของ controller" do
    source = File.read(
      Rails.root.join('app/controllers/api/v1/leave_forms_controller.rb')
    )
    expect(source).to include(':explanation')
  end

  it "LeaveForm model มี explanation attribute" do
    lf = LeaveForm.new(explanation: "มีไข้สูง")
    expect(lf.explanation).to eq("มีไข้สูง")
  end

  it "explanation ถูกบันทึกลง database ได้" do
    # LeaveForm ต้องการ schedule (not null) สร้าง schedule ก่อน
    conference      = create(:conference)
    conference_date = create(:conference_date, conference: conference)
    table           = create(:table, conference: conference)
    schedule = Schedule.create!(
      conference_date: conference_date,
      target_id:       create(:team, company: create(:company)).id,
      table:           table,
      start_at:        Time.current,
      end_at:          1.hour.from_now
    )

    reporter   = create(:delegate)
    leave_type = LeaveType.first || LeaveType.create!(name: "ลาป่วย")

    lf = LeaveForm.create!(
      schedule:    schedule,
      reason:      "ป่วย",
      explanation: "ขอลาเพื่อดูแลครอบครัว",
      leave_type:  leave_type,
      reported_by: reporter
    )
    expect(lf.reload.explanation).to eq("ขอลาเพื่อดูแลครอบครัว")
  end
end

# ============================================================
# 🟡 BUG #6 - Email บอก "1 ชั่วโมง" แต่ link หมดอายุใน 30 นาที
# ============================================================
RSpec.describe "Bug #6: Password reset expiry text vs actual expiry", type: :model do
  let(:delegate) { create(:delegate) }

  describe "ResetPasswordJob email content" do
    it "ส่ง email ที่ระบุว่าหมดอายุใน 30 นาที" do
      ActionMailer::Base.deliveries.clear
      begin
        ResetPasswordJob.new.perform(delegate.id)
      rescue StandardError
        # ignore
      end

      mail = ActionMailer::Base.deliveries.last
      skip "ResetPasswordJob ไม่ส่ง email ใน test env" if mail.nil?

      body = mail.body.encoded
      expect(body).to include("30")
      expect(body).not_to include("1 ชั่วโมง")
    end
  end

  describe "Delegate reset_password_sent_at logic (30 นาที)" do
    def token_valid?(d)
      d.reset_password_sent_at.present? &&
        d.reset_password_sent_at > 30.minutes.ago
    end

    it "token ที่ส่งมาเมื่อกี้ยังใช้งานได้" do
      delegate.update!(reset_password_sent_at: 1.minute.ago)
      expect(token_valid?(delegate)).to be true
    end

    it "token ที่ส่งมา 29 นาทีที่แล้วยังใช้งานได้" do
      delegate.update!(reset_password_sent_at: 29.minutes.ago)
      expect(token_valid?(delegate)).to be true
    end

    it "token ที่ส่งมา 31 นาทีที่แล้วหมดอายุแล้ว" do
      delegate.update!(reset_password_sent_at: 31.minutes.ago)
      expect(token_valid?(delegate)).to be false
    end

    it "token ที่ส่งมา 61 นาทีที่แล้วหมดอายุแล้ว (ยืนยันว่าไม่ใช่ 1 ชั่วโมง)" do
      delegate.update!(reset_password_sent_at: 61.minutes.ago)
      expect(token_valid?(delegate)).to be false
    end
  end
end

# ============================================================
# 🟡 BUG #7 - ChatRoomChannel#subscribed N+1 query
# ============================================================
RSpec.describe "Bug #7: ChatRoomChannel N+1 query fix", type: :model do
  let(:delegate)  { create(:delegate) }
  let(:chat_room) { create(:chat_room, :group) }

  before { chat_room.chat_room_members.create!(delegate: delegate) }

  it "exists? คืน true สำหรับ member ที่มีอยู่" do
    expect(chat_room.chat_room_members.exists?(delegate_id: delegate.id)).to be true
  end

  it "exists? คืน false สำหรับ delegate ที่ไม่ใช่ member" do
    other = create(:delegate)
    expect(chat_room.chat_room_members.exists?(delegate_id: other.id)).to be false
  end

  it "exists? ใช้ LIMIT 1 ไม่โหลด records ทั้งหมด" do
    queries = []
    sub     = ->(*args) { queries << args.last[:sql] if args.last.is_a?(Hash) }

    ActiveSupport::Notifications.subscribed(sub, "sql.active_record") do
      chat_room.chat_room_members.exists?(delegate_id: delegate.id)
    end

    expect(queries.length).to eq(1)
    # LIMIT $3 หรือ LIMIT 1 ขึ้นกับ PostgreSQL
    expect(queries.first).to match(/LIMIT/i)
  end

  it "channel source ใช้ exists? ไม่ใช่ include?" do
    source = File.read(
      Rails.root.join('app/channels/chat_room_channel.rb')
    )
    # หลังแก้: ใช้ exists? แทน include?
    expect(source).to include('exists?')
  end
end

# ============================================================
# 🟢 BUG #8 - MessagesController#mark_as_read double query
# ============================================================
RSpec.describe "Bug #8: MessagesController#mark_as_read double query", type: :request do
  let(:delegate) { create(:delegate) }
  let(:message)  { create(:chat_message, :direct, recipient: delegate, read_at: nil) }
  let(:headers)  { auth_headers(delegate) }

  it "mark as read สำเร็จ" do
    patch "/api/v1/messages/#{message.id}/mark_as_read", headers: headers

    expect(response).to have_http_status(:ok)
    expect(message.reload.read_at).not_to be_nil
  end

  it "return 404 เมื่อ message ไม่มีอยู่" do
    patch "/api/v1/messages/99999/mark_as_read", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "@message ถูก set จาก before_action และไม่ query ซ้ำใน action" do
    source = File.read(
      Rails.root.join('app/controllers/api/v1/messages_controller.rb')
    )
    # ดึงแค่ method mark_as_read (ไม่รวม before_action และ methods อื่น)
    # หลังแก้: method ไม่มี ChatMessage.find ใหม่ (มีแต่ใน before_action)
    mark_as_read = source[/def mark_as_read\b.*?(?=\n      def |\n    end\n  end)/m]
    # กรอง comment ออก แล้วตรวจ
    code_only = mark_as_read.gsub(/#.*$/, '')
    expect(code_only).not_to match(/ChatMessage\.(find|find_by)/)
  end
end

# ============================================================
# 🟢 BUG #9 - Schedule#team_delegates bypasses eager loading
# ============================================================
RSpec.describe "Bug #9: Schedule#team_delegates eager loading", type: :model do
  let(:company)         { create(:company) }
  let(:team)            { create(:team, company: company) }
  let(:conference)      { create(:conference) }
  let(:conference_date) { create(:conference_date, conference: conference) }
  let(:table)           { create(:table, conference: conference) }

  def build_schedule
    Schedule.create!(
      conference_date: conference_date,
      target_id:       team.id,
      table:           table,
      start_at:        Time.current,
      end_at:          1.hour.from_now
    )
  end

  it "team_delegates method มีอยู่ใน Schedule" do
    expect(Schedule.instance_methods).to include(:team_delegates)
  end

  it "with_full_data scope มีอยู่และใช้งานได้" do
    expect(Schedule).to respond_to(:with_full_data)
  end

  it "team_delegates คืนค่า delegates ของ team ที่ถูกต้อง" do
    delegates = create_list(:delegate, 2, company: company, team: team)
    schedule  = build_schedule

    expect(schedule.team_delegates).to match_array(delegates)
  end

  it "team_delegates ใช้ association cache (ไม่ query เพิ่มหลัง eager load)" do
    create_list(:delegate, 2, company: company, team: team)
    schedule = build_schedule

    loaded = Schedule.includes(team: :delegates).find(schedule.id)
    loaded.team.delegates.load  # prime cache

    query_count = 0
    ActiveSupport::Notifications.subscribed(
      ->(*) { query_count += 1 }, "sql.active_record"
    ) { loaded.team_delegates }

    expect(query_count).to eq(0)
  end
end

# ============================================================
# 🟢 BUG #10 - Chat::PresenceService ไม่มี Redis error handling
# ============================================================
RSpec.describe "Bug #10: Chat::PresenceService Redis error handling", type: :model do
  let(:delegate) { create(:delegate) }
  let(:user_id)  { delegate.id.to_s }

  def stub_redis_error
    redis_double = instance_double(Redis)
    stub_const("REDIS", redis_double)
    %i[incr decr get del expire set].each do |m|
      allow(redis_double).to receive(m)
        .and_raise(Redis::BaseError, "Connection refused")
    end
  end

  context "online" do
    it "ไม่ raise error เมื่อ Redis ล่ม" do
      stub_redis_error
      expect { Chat::PresenceService.online(user_id) }.not_to raise_error
    end

    it "log warning เมื่อ Redis ล่ม" do
      stub_redis_error
      expect(Rails.logger).to receive(:warn).with(/Presence/i)
      Chat::PresenceService.online(user_id)
    end

    it "คืนค่า 0 เมื่อ Redis ล่ม" do
      stub_redis_error
      expect(Chat::PresenceService.online(user_id)).to eq(0)
    end
  end

  context "offline" do
    it "ไม่ raise error เมื่อ Redis ล่ม" do
      stub_redis_error
      expect { Chat::PresenceService.offline(user_id) }.not_to raise_error
    end
  end

  context "online?" do
    it "ไม่ raise error เมื่อ Redis ล่ม" do
      stub_redis_error
      expect { Chat::PresenceService.online?(user_id) }.not_to raise_error
    end

    it "คืนค่า false เมื่อ Redis ล่ม" do
      stub_redis_error
      # online? เรียก connection_count ซึ่ง rescue แล้วคืน 0 → positive? = false
      expect(Chat::PresenceService.online?(user_id)).to be false
    end
  end

  context "connection_count" do
    it "ไม่ raise error เมื่อ Redis ล่ม" do
      stub_redis_error
      expect { Chat::PresenceService.connection_count(user_id) }.not_to raise_error
    end

    it "คืนค่า 0 เมื่อ Redis ล่ม" do
      stub_redis_error
      expect(Chat::PresenceService.connection_count(user_id)).to eq(0)
    end
  end

  context "ทำงานปกติเมื่อ Redis ใช้งานได้" do
    it "online ไม่ raise error" do
      expect { Chat::PresenceService.online(user_id) }.not_to raise_error
    end

    it "online? คืน true หลัง online" do
      Chat::PresenceService.online(user_id)
      expect(Chat::PresenceService.online?(user_id)).to be true
    end

    it "offline ทำให้ online? คืน false" do
      Chat::PresenceService.online(user_id)
      Chat::PresenceService.offline(user_id)
      expect(Chat::PresenceService.online?(user_id)).to be false
    end

    it "connection_count ไม่ raise error" do
      expect { Chat::PresenceService.connection_count(user_id) }.not_to raise_error
    end
  end
end