# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  # 🔴 FIX 1: has_one ด้วย foreign_key: 'id', primary_key: 'id' ผิด
  # มันบอก Rails ว่า delegates.id = users.id ซึ่งไม่ใช่ความสัมพันธ์จริง
  # ควรใช้ foreign_key: 'user_id' บนตาราง delegates แทน
  has_one :delegate_profile, class_name: 'Delegate', foreign_key: 'user_id'

  # 🔴 FIX 2: Knock gem ถูก comment ออกจาก Gemfile แล้ว → NameError ทันทีที่เรียก method นี้
  # เปลี่ยนมาใช้ JWT ให้ consistent กับทั้ง project
  def auth_token
    payload = {
      sub: id,
      exp: JWT_CONFIG[:expiration_time].from_now.to_i,
      iss: JWT_CONFIG[:issuer]
    }

    JWT.encode(payload, JWT_CONFIG[:secret], JWT_CONFIG[:algorithm])
  end
end