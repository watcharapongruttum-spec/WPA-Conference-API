#!/bin/bash
# fix_chat_system.sh
# รันจากโฟลเดอร์หลักของโปรเจกต์: ~/mikkee_pro/WPA-Conference-API

set -e

# เปลี่ยนไปยังโฟลเดอร์หลักของโปรเจกต์
cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "ℹ️  $1"; }

echo "=========================================="
echo "🔧 แก้ไขปัญหาทั้งหมดในระบบแชท"
echo "=========================================="
echo ""

# ================= 1. ตรวจสอบโครงสร้างโฟลเดอร์ =================
print_info "1. ตรวจสอบโครงสร้างโปรเจกต์..."
if [ ! -d "app/models" ] || [ ! -d "app/controllers/api/v1" ]; then
    print_error "ไม่พบโครงสร้างโปรเจกต์ที่ถูกต้อง!"
    print_info "รันสคริปต์นี้จาก: ~/mikkee_pro/WPA-Conference-API"
    exit 1
fi
print_success "โครงสร้างโปรเจกต์ถูกต้อง"
echo ""

# ================= 2. สำรองไฟล์เดิม =================
print_info "2. สำรองไฟล์เดิม..."
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in app/models/chat_message.rb app/controllers/api/v1/messages_controller.rb app/controllers/api/v1/profile_controller.rb config/routes.rb; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/"
        print_success "สำรอง $file -> $BACKUP_DIR/"
    fi
done
echo ""

# ================= 3. แก้ไข ChatMessage model =================
print_info "3. แก้ไข ChatMessage model..."

cat > app/models/chat_message.rb << 'EOF'
class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient, class_name: "Delegate", optional: true
  
  validates :content, presence: true
  validate :direct_or_room_chat
  
  scope :unread, -> { where(read_at: nil) }
  
  private
  
  def direct_or_room_chat
    # ตรวจสอบว่าต้องมีอย่างน้อย 1 อย่าง
    if chat_room_id.nil? && recipient_id.nil?
      errors.add(:base, "Message must have recipient or chat_room")
    end
    
    # ตรวจสอบว่าไม่สามารถมีทั้งสองอย่างพร้อมกัน
    if chat_room_id.present? && recipient_id.present?
      errors.add(:base, "Message cannot have both recipient and chat_room")
    end
  end
  
  def can_send_message?
    # ถ้าไม่มี chat_room ให้ return true (เป็นแชท 1:1)
    return true if chat_room.nil?
    
    # ถ้ามี chat_room ให้ตรวจสอบสิทธิ์
    chat_room.can_send_message?(sender)
  end
end
EOF

print_success "แก้ไข ChatMessage model สำเร็จ"
echo ""

# ================= 4. แก้ไข MessagesController =================
print_info "4. แก้ไข MessagesController..."

mkdir -p app/controllers/api/v1

cat > app/controllers/api/v1/messages_controller.rb << 'EOF'
module Api
  module V1
    class MessagesController < BaseController
      before_action :authenticate_delegate
      
      # POST /api/v1/messages
      def create
        @message = ChatMessage.new(message_params)
        @message.sender = current_delegate
        
        if @message.save
          # ส่งข้อความไปยังผู้ส่ง
          ChatChannel.broadcast_to(
            current_delegate,
            type: 'new_message',
            message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
          )
          
          # ส่งข้อความไปยังผู้รับ (ถ้าเป็นแชท 1:1)
          if @message.recipient
            ChatChannel.broadcast_to(
              @message.recipient,
              type: 'new_message',
              message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
            )
          end
          
          # สร้างการแจ้งเตือน
          if @message.recipient
            Notification.create!(
              delegate: @message.recipient,
              notification_type: 'new_message',
              notifiable: @message
            )
            
            # ส่งการแจ้งเตือนเรียลไทม์
            NotificationChannel.broadcast_to(
              @message.recipient,
              type: 'new_notification',
              notification: Api::V1::NotificationSerializer.new(
                Notification.last,
                scope: @message.recipient
              ).serializable_hash
            )
          end
          
          render json: @message, serializer: Api::V1::ChatMessageSerializer, status: :created
        else
          render json: { 
            error: 'Failed to send message', 
            errors: @message.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end
      
      # GET /api/v1/messages/conversation/:delegate_id
      def conversation
        recipient = Delegate.find(params[:delegate_id])
        
        @messages = ChatMessage.where(
          "(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)",
          current_delegate.id,
          recipient.id,
          recipient.id,
          current_delegate.id
        ).includes(:sender, :recipient).order(created_at: :asc)
        
        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end
      
      # PATCH /api/v1/messages/:id/mark_as_read
      def mark_as_read
        @message = ChatMessage.find(params[:id])
        
        if @message.recipient != current_delegate
          render json: { error: 'Unauthorized' }, status: :forbidden
          return
        end
        
        @message.update(read_at: Time.current)
        
        render json: { message: 'Marked as read' }
      end
      
      private
      
      def message_params
        params.permit(:recipient_id, :content)
      end
    end
  end
end
EOF

print_success "แก้ไข MessagesController สำเร็จ"
echo ""

# ================= 5. แก้ไข ProfileController =================
print_info "5. แก้ไข ProfileController..."

cat > app/controllers/api/v1/profile_controller.rb << 'EOF'
module Api
  module V1
    class ProfileController < BaseController
      before_action :authenticate_delegate
      
      # GET /api/v1/profile
      def show
        delegate = current_delegate
        
        render json: {
          id: delegate.id,
          name: delegate.name,
          title: delegate.title,
          email: delegate.email,
          phone: delegate.phone,
          company: {
            id: delegate.company.id,
            name: delegate.company.name,
            country: delegate.company.country,
            logo_url: delegate.company.logo.attached? ? rails_blob_url(delegate.company.logo) : nil
          },
          avatar_url: delegate.avatar.attached? ? rails_blob_url(delegate.avatar) : "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff",
          team: delegate.team ? {
            id: delegate.team.id,
            name: delegate.team.name,
            country_code: delegate.team.country_code
          } : nil,
          first_conference: delegate.first_conference,
          spouse_attending: delegate.spouse_attending,
          spouse_name: delegate.spouse_name,
          need_room: delegate.need_room,
          booking_no: delegate.booking_no
        }
      end
      
      # PATCH /api/v1/profile
      def update
        if current_delegate.update(delegate_params)
          render json: {
            id: current_delegate.id,
            name: current_delegate.name,
            title: current_delegate.title,
            email: current_delegate.email,
            phone: current_delegate.phone
          }
        else
          render json: { 
            error: 'Failed to update profile', 
            errors: current_delegate.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end
      
      private
      
      def delegate_params
        params.permit(:name, :title, :phone)
      end
    end
  end
end
EOF

print_success "แก้ไข ProfileController สำเร็จ"
echo ""

# ================= 6. แก้ไข Routes =================
print_info "6. แก้ไข Routes..."

# ตรวจสอบว่ามีเส้นทาง PATCH /profile แล้วหรือไม่
if grep -q "patch 'profile'" config/routes.rb; then
    print_warning "เส้นทาง PATCH /profile มีอยู่แล้ว"
else
    # เพิ่มเส้นทางใหม่หลังจากเส้นทาง GET /profile
    sed -i "/get 'profile'/a\      patch 'profile', to: 'profile#update'" config/routes.rb
    print_success "เพิ่มเส้นทาง PATCH /profile สำเร็จ"
fi
echo ""

# ================= 7. สร้าง Serializers =================
print_info "7. สร้าง Serializers..."

mkdir -p app/serializers/api/v1

# ChatMessageSerializer
cat > app/serializers/api/v1/chat_message_serializer.rb << 'EOF'
module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :created_at, :read_at, :sender, :recipient
      
      def sender
        {
          id: object.sender.id,
          name: object.sender.name,
          title: object.sender.title,
          company: object.sender.company&.name || 'N/A',
          avatar_url: begin
            Api::V1::DelegateSerializer.new(object.sender).avatar_url
          rescue => e
            "https://ui-avatars.com/api/?name=#{CGI.escape(object.sender.name)}&background=0D8ABC&color=fff"
          end
        }
      end
      
      def recipient
        if object.recipient
          {
            id: object.recipient.id,
            name: object.recipient.name,
            title: object.recipient.title,
            company: object.recipient.company&.name || 'N/A',
            avatar_url: begin
              Api::V1::DelegateSerializer.new(object.recipient).avatar_url
            rescue => e
              "https://ui-avatars.com/api/?name=#{CGI.escape(object.recipient.name)}&background=0D8ABC&color=fff"
            end
          }
        else
          nil
        end
      end
    end
  end
end
EOF

print_success "สร้าง ChatMessageSerializer สำเร็จ"

# NotificationSerializer
cat > app/serializers/api/v1/notification_serializer.rb << 'EOF'
module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      attributes :id, :notification_type, :created_at, :read_at, :content, :sender
      
      def content
        case object.notification_type
        when 'new_message'
          message = object.notifiable
          "#{message.sender.name}: #{message.content.truncate(50)}"
        when 'connection_request'
          "#{object.notifiable.requester.name} wants to connect with you"
        when 'connection_accepted'
          "#{object.notifiable.requester.name} accepted your connection request"
        else
          'New notification'
        end
      end
      
      def sender
        if object.notification_type == 'new_message' && object.notifiable.is_a?(ChatMessage)
          {
            id: object.notifiable.sender.id,
            name: object.notifiable.sender.name,
            avatar_url: begin
              Api::V1::DelegateSerializer.new(object.notifiable.sender).avatar_url
            rescue => e
              "https://ui-avatars.com/api/?name=#{CGI.escape(object.notifiable.sender.name)}&background=0D8ABC&color=fff"
            end
          }
        else
          nil
        end
      end
    end
  end
end
EOF

print_success "สร้าง NotificationSerializer สำเร็จ"
echo ""

# ================= 8. สร้างข้อมูลทดสอบ =================
print_info "8. สร้างข้อมูลทดสอบ..."

rails runner "
  begin
    # ตรวจสอบผู้ใช้ที่จำเป็น
    delegates_needed = [205, 206, 238]
    delegates_needed.each do |id|
      unless Delegate.exists?(id)
        Delegate.create!(
          id: id,
          name: \"Test User #{id}\",
          email: \"test#{id}@example.com\",
          password: 'temporary',
          company_id: 1
        )
        puts \"สร้างผู้ใช้ ID #{id} สำเร็จ\"
      end
    end
    
    # สร้างห้องแชททดสอบ
    puts 'สร้างห้องแชททดสอบ...'
    
    # ห้องแชท 1:1
    room1 = ChatRoom.find_or_create_by!(title: 'Test DM', room_kind: 'direct')
    RoomMember.find_or_create_by!(chat_room: room1, delegate_id: 206)
    RoomMember.find_or_create_by!(chat_room: room1, delegate_id: 205)
    
    # ห้องแชทกลุ่ม
    room2 = ChatRoom.find_or_create_by!(title: 'Test Group', room_kind: 'group')
    RoomMember.find_or_create_by!(chat_room: room2, delegate_id: 206)
    RoomMember.find_or_create_by!(chat_room: room2, delegate_id: 205)
    RoomMember.find_or_create_by!(chat_room: room2, delegate_id: 238)
    
    # ห้องประกาศ
    room3 = ChatRoom.find_or_create_by!(title: 'Announcements', room_kind: 'broadcast')
    admin_member = RoomMember.find_or_create_by!(chat_room: room3, delegate_id: 238)
    admin_member.update(role: 'admin')
    RoomMember.find_or_create_by!(chat_room: room3, delegate_id: 206, role: 'member')
    RoomMember.find_or_create_by!(chat_room: room3, delegate_id: 205, role: 'member')
    
    puts '✅ สร้างห้องแชททดสอบสำเร็จ'
    puts \"   - DM Room: #{room1.id}\"
    puts \"   - Group Room: #{room2.id}\"
    puts \"   - Broadcast Room: #{room3.id}\"
    
    exit 0
  rescue => e
    puts \"❌ Error: #{e.message}\"
    puts e.backtrace.first(5).join(\"\\n\")
    exit 1
  end
" && print_success "สร้างข้อมูลทดสอบสำเร็จ" || print_error "สร้างข้อมูลทดสอบล้มเหลว"
echo ""

# ================= 9. สรุปผล =================
echo "=========================================="
echo "📊 สรุปผลการแก้ไข"
echo "=========================================="
echo ""
print_success "✅ แก้ไข ChatMessage model"
print_success "✅ แก้ไข MessagesController"
print_success "✅ แก้ไข ProfileController"
print_success "✅ แก้ไข Routes (เพิ่ม PATCH /profile)"
print_success "✅ สร้าง ChatMessageSerializer"
print_success "✅ สร้าง NotificationSerializer"
print_success "✅ สร้างข้อมูลทดสอบ"
echo ""
print_info "💡 คำแนะนำต่อไป:"
echo "   1. รีสตาร์ทเซิร์ฟเวอร์: Ctrl+C แล้วรัน 'rails s' ใหม่"
echo "   2. รันสคริปต์ทดสอบ: cd test_scripts && ./test_all_system.sh"
echo "   3. ทดสอบกับ UI จริง"
echo ""
print_success "🎉 แก้ไขปัญหาทั้งหมดเสร็จสิ้น!"
echo ""
print_info "📁 ไฟล์ที่สำรองไว้ใน: $BACKUP_DIR"