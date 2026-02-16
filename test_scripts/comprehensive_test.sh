#!/bin/bash
echo "=========================================="
echo "ทดสอบระบบแชทแบบครบวงจร"
echo "=========================================="
echo ""

# สีสำหรับการแสดงผล
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ฟังก์ชันสำหรับแสดงผลลัพธ์
print_result() {
  if [ $1 -eq 0 ]; then
    echo -e "${GREEN}✅ $2${NC}"
  else
    echo -e "${RED}❌ $2${NC}"
  fi
}

# 1. ตรวจสอบโครงสร้างฐานข้อมูล
echo "1. ตรวจสอบโครงสร้างฐานข้อมูล..."
rails runner "
  exit(1) unless ChatMessage.column_names.include?('chat_room_id') || ChatMessage.column_names.include?('room_id')
  exit(1) unless ChatMessage.column_names.include?('recipient_id')
  exit(1) unless ChatMessage.reflect_on_association(:sender)
" > /dev/null 2>&1
print_result $? "โครงสร้างฐานข้อมูลถูกต้อง"

# 2. ทดสอบการสร้างข้อความ
echo "2. ทดสอบการสร้างข้อความ..."
rails runner "
  begin
    message = ChatMessage.create!(
      sender_id: 206,
      recipient_id: 205,
      content: 'ทดสอบข้อความ'
    )
    exit(0)
  rescue => e
    puts e.message
    exit(1)
  end
" > /dev/null 2>&1
print_result $? "สร้างข้อความสำเร็จ"

# 3. ทดสอบการสร้างห้องแชท
echo "3. ทดสอบการสร้างห้องแชท..."
rails runner "
  begin
    room = ChatRoom.create!(title: 'ทดสอบ', room_kind: 'group')
    RoomMember.create!(chat_room: room, delegate_id: 206)
    RoomMember.create!(chat_room: room, delegate_id: 205)
    exit(0)
  rescue => e
    puts e.message
    exit(1)
  end
" > /dev/null 2>&1
print_result $? "สร้างห้องแชทสำเร็จ"

# 4. ทดสอบการสร้างการแจ้งเตือน
echo "4. ทดสอบการสร้างการแจ้งเตือน..."
rails runner "
  begin
    notification = Notification.create!(
      delegate_id: 205,
      type: 'test',
      notifiable_type: 'ChatMessage',
      notifiable_id: 1
    )
    exit(0)
  rescue => e
    puts e.message
    exit(1)
  end
" > /dev/null 2>&1
print_result $? "สร้างการแจ้งเตือนสำเร็จ"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}การทดสอบเสร็จสิ้น!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "สรุปผลการทดสอบ:"
echo "✅ = ผ่าน"
echo "❌ = ไม่ผ่าน (ต้องแก้ไข)"
