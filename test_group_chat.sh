#!/bin/bash
echo "=========================================="
echo "ทดสอบการสร้างห้องแชทกลุ่มและการส่งข้อความ"
echo "=========================================="

rails runner "
  puts '1. สร้างห้องแชทกลุ่มใหม่...'
  room = ChatRoom.create!(title: 'ห้องทดสอบกลุ่ม', room_kind: 'group')
  puts \"✅ สร้างห้องสำเร็จ: #{room.id} - #{room.title}\"
  
  puts ''
  puts '2. เพิ่มสมาชิกในห้อง (ผู้ใช้ ID 206 และ 205)...'
  RoomMember.create!(chat_room: room, delegate_id: 206)
  RoomMember.create!(chat_room: room, delegate_id: 205)
  puts \"✅ เพิ่มสมาชิกสำเร็จ: #{room.delegates.count} คน\"
  
  puts ''
  puts '3. ส่งข้อความในห้อง...'
  message = ChatMessage.create!(
    chat_room: room,
    sender_id: 206,
    content: 'สวัสดีทุกคนในห้องกลุ่ม!'
  )
  puts \"✅ ส่งข้อความสำเร็จ: #{message.id}\"
  
  puts ''
  puts '4. ตรวจสอบข้อความในห้อง...'
  messages = room.chat_messages
  puts \"✅ มีข้อความในห้อง: #{messages.count} ข้อความ\"
  messages.each do |msg|
    puts \"   - #{msg.sender.name}: #{msg.content}\"
  end
"
