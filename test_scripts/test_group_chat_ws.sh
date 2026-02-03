#!/bin/bash
# test_group_chat_ws.sh
# ทดสอบแชทกลุ่มแบบเรียลไทม์

echo "=========================================="
echo "🧪 ทดสอบแชทกลุ่มแบบเรียลไทม์"
echo "=========================================="
echo ""

# สร้างห้องแชทกลุ่มก่อน
echo "1. สร้างห้องแชทกลุ่ม..."
rails runner "
    room = ChatRoom.where(title: 'ห้องทดสอบกลุ่ม').first || 
           ChatRoom.create!(title: 'ห้องทดสอบกลุ่ม', room_kind: 'group')
    
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 206)
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 205)
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 238)
    
    puts \"ห้อง: #{room.id}\"
    puts \"สมาชิก: #{room.delegates.pluck(:id).inspect}\"
" > /tmp/room_info.txt

ROOM_ID=$(grep "ห้อง:" /tmp/room_info.txt | cut -d' ' -f2)
echo "✅ สร้างห้องสำเร็จ: $ROOM_ID"
echo ""

# แสดงคำสั่งสำหรับผู้ใช้แต่ละคน
echo "📋 คำแนะนำ:"
echo ""
echo "เปิด 3 หน้าต่างเทอร์มินัล:"
echo ""
echo "หน้าต่างที่ 1 (ผู้ใช้ 206):"
echo "TOKEN=\"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE\""
echo "wscat -c \"ws://localhost:3000/cable?token=\$TOKEN\" -H \"Origin: http://localhost:3000\""
echo ""
echo "หน้าต่างที่ 2 (ผู้ใช้ 205):"
echo "TOKEN=\"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA1LCJleHAiOjE3Njk3NjE1NDMsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.kwE1tnSuKSMP0pe7sXNUY6fVeI3aYLvX6K0X04WZefY\""
echo "wscat -c \"ws://localhost:3000/cable?token=\$TOKEN\" -H \"Origin: http://localhost:3000\""
echo ""
echo "หน้าต่างที่ 3 (ผู้ใช้ 238):"
echo "TOKEN=\"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjM4LCJleHAiOjE3Njk4MjgzNzcsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.9qW1lyRnCVk4NVFFfR5rfwdez7Zz9BzG6X_a5WNOgdk\""
echo "wscat -c \"ws://localhost:3000/cable?token=\$TOKEN\" -H \"Origin: http://localhost:3000\""
echo ""
echo "ในแต่ละหน้าต่าง พิมพ์ (บรรทัดเดียว):"
echo "{\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"ChatRoomChannel\\\",\\\"room_id\\\":$ROOM_ID}\"}"
echo ""
echo "จากนั้นส่งข้อความ (ในหน้าต่างใดก็ได้):"
echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatRoomChannel\\\",\\\"room_id\\\":$ROOM_ID}\",\"data\":\"{\\\"action\\\":\\\"send_message\\\",\\\"content\\\":\\\"สวัสดีทุกคนในห้อง!\\\"}\"}"
echo ""
echo "✅ ทุกคนในห้องจะเห็นข้อความทันที!"