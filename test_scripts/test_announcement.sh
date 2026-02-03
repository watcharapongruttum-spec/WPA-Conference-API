#!/bin/bash
# test_announcement.sh
# ทดสอบระบบประกาศ/บอร์ดแคช

echo "=========================================="
echo "📢 ทดสอบระบบประกาศ (Broadcast)"
echo "=========================================="
echo ""

echo "1. สร้างห้องประกาศ..."
rails runner "
    # สร้างห้องประกาศ
    room = ChatRoom.where(title: 'Announcements').first || 
           ChatRoom.create!(title: 'Announcements', room_kind: 'broadcast')
    
    # เพิ่มแอดมิน
    admin_member = RoomMember.find_or_create_by!(
        chat_room: room,
        delegate_id: 238
    )
    admin_member.update(role: 'admin')
    
    # เพิ่มสมาชิก
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 206)
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 205)
    
    puts \"ห้องประกาศ: #{room.id}\"
    puts \"แอดมิน: #{room.room_members.where(role: 'admin').first.delegate.name}\"
    puts \"สมาชิก: #{room.room_members.where(role: 'member').count} คน\"
" > /tmp/announcement_info.txt

echo "✅ สร้างห้องประกาศสำเร็จ"
echo ""

echo "2. ทดสอบแอดมินส่งประกาศ..."
rails runner "
    room = ChatRoom.find_by(title: 'Announcements')
    message = room.chat_messages.create!(
        sender_id: 238,
        content: '📢 ประกาศสำคัญ: การประชุมจะเริ่มเวลา 09:00 น.'
    )
    puts \"✅ ส่งประกาศสำเร็จ: #{message.id}\"
"

echo ""
echo "3. ทดสอบสมาชิกส่งประกาศ (ควรล้มเหลว)..."
rails runner "
    room = ChatRoom.find_by(title: 'Announcements')
    begin
        message = room.chat_messages.create!(
            sender_id: 206,
            content: 'ทดสอบส่งประกาศ'
        )
        puts \"❌ สมาชิกส่งประกาศได้ (ไม่ควรเป็นไปได้)\"
        exit 1
    rescue => e
        puts \"✅ สมาชิกส่งประกาศล้มเหลว (ถูกต้อง): #{e.message}\"
        exit 0
    end
"

echo ""
echo "=========================================="
echo "✅ การทดสอบระบบประกาศเสร็จสิ้น"
echo "=========================================="