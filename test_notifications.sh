#!/bin/bash
echo "=========================================="
echo "ทดสอบการแจ้งเตือนเรียลไทม์"
echo "=========================================="

rails runner "
  puts '1. สร้างการแจ้งเตือนใหม่...'
  notification = Notification.create!(
    delegate_id: 205,
    type: 'new_message',
    notifiable_type: 'ChatMessage',
    notifiable_id: 1
  )
  puts \"✅ สร้างการแจ้งเตือนสำเร็จ: #{notification.id}\"
  
  puts ''
  puts '2. ตรวจสอบการแจ้งเตือนของผู้ใช้...'
  notifications = Delegate.find(205).notifications
  puts \"✅ มีการแจ้งเตือน: #{notifications.count} รายการ\"
  notifications.each do |notif|
    puts \"   - #{notif.type} (#{notif.created_at})\"
  end
  
  puts ''
  puts '3. ทำเครื่องหมายการแจ้งเตือนว่าอ่านแล้ว...'
  notification.mark_as_read!
  puts \"✅ ทำเครื่องหมายว่าอ่านแล้ว: #{notification.read_at}\"
"
