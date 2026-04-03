# 📘 WPA Conference API (Realtime Chat & Notification System)

Backend API สำหรับระบบ Conference ที่รองรับ Realtime Chat, Group Chat และ Notification ผ่าน WebSocket (ActionCable)

---

## 🚀 Tech Stack

* **Ruby on Rails (API Mode)**
* **PostgreSQL**
* **Redis**
* **ActionCable (WebSocket)**
* **JWT Authentication**

---

## 📦 Features

### 💬 Direct Chat (1-1)

* ส่งข้อความ / รูปภาพ
* Read receipt (`read_at`)
* Typing indicator
* Online presence (Realtime)
* Auto mark read เมื่อผู้รับเปิดห้องอยู่

---

### 👥 Group Chat

* สร้างห้องแชท
* Join / Leave ห้อง
* ส่งข้อความ / รูปภาพ
* Edit / Delete message
* Typing indicator
* Bulk read ผ่าน `message_reads`

---

### 🔔 Notifications

* Realtime ผ่าน WebSocket
* รองรับ:

  * `new_message`
  * `new_group_message`
  * `system notifications`

---

### 📊 Dashboard

* unread messages (direct + group)
* pending requests
* upcoming schedules
* connections count

---

### 🔐 Authentication

* JWT Token
* Token version control (force logout ได้)
* รองรับ token expiry

---

## ⚙️ Installation

```bash
git clone <repo-url>
cd project

bundle install

rails db:create
rails db:migrate

rails s
```

---

## 🔑 Environment Variables

```env
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
JWT_SECRET=your_secret
```

---

## 🔌 WebSocket (ActionCable)

### Connection

```
ws://localhost:3000/cable?token=JWT_TOKEN
```

---

### Frontend Example

```js
import { createConsumer } from "@rails/actioncable"

const cable = createConsumer(
  `ws://localhost:3000/cable?token=${token}`
)
```

---

## 📡 Channels

### 1. ChatChannel (Direct Chat)

#### Events

* `send_message`
* `send_image`
* `typing_start`
* `typing_stop`
* `enter_room`
* `leave_room`
* `ping`

#### Payload Example

```json
{
  "recipient_id": 123,
  "content": "Hello"
}
```

---

### 2. GroupChatChannel

#### Events

* `speak`
* `send_image`
* `edit_message`
* `delete_message`
* `typing`
* `stop_typing`
* `enter_room`
* `leave_room`

---

### 3. NotificationChannel

ใช้สำหรับรับ notification realtime

---

## 🧠 Core Concepts

### 🟢 Presence System

* เก็บใน Redis
* track online/offline user
* refresh ด้วย `ping`

---

### 🏠 Active Room Tracking

ใช้ Redis key:

```
chat:active_room:<user_id>
group_chat_open:<room_id>:<user_id>
```

ใช้เพื่อ:

* skip notification ถ้า user กำลังอ่าน
* auto mark read

---

### ✅ Read Logic

#### Direct Chat

ใช้ field:

```
chat_messages.read_at
```

#### Group Chat

ใช้ table:

```
message_reads
```

---

### 🔔 Notification Pipeline

```ruby
Notifications::Pipeline.call(message)
```

จะไม่ส่ง notification ถ้า:

* message ถูกอ่านแล้ว (`read_at` มีค่า)

---

## 📁 Project Structure

```
app/
├── channels/
│   ├── chat_channel.rb
│   ├── group_chat_channel.rb
│   ├── notification_channel.rb
│
├── controllers/api/v1/
│   ├── chat_rooms_controller.rb
│   ├── dashboard_controller.rb
│   ├── delegates_controller.rb
│
├── services/
│   ├── chat/
│   ├── notifications/
│
├── constants/
│   ├── chat_keys.rb
│   ├── ws_events.rb
```

---

## 🔐 API Authentication

Header:

```
Authorization: Bearer <JWT_TOKEN>
```

---

## 📊 Dashboard API

```
GET /api/v1/dashboard
```

### Response

```json
{
  "unread_notifications_count": 5,
  "new_messages_count": 10,
  "pending_requests_count": 2,
  "upcoming_schedule_count": 4,
  "connections_count": 20
}
```

---

## 🧪 Error Handling

| Status | Description             |
| ------ | ----------------------- |
| 404    | Record not found        |
| 422    | Validation failed       |
| 401    | Invalid / expired token |
| 500    | Unexpected error        |

---

## 🧹 Deprecated

### AnnouncementChannel

❌ ไม่ถูกใช้งานแล้ว
👉 ใช้ NotificationChannel แทน

---

## ⚠️ Important Notes

* Redis จำเป็นสำหรับ:

  * Presence
  * Active room
  * Typing
* Group chat ใช้ logic ต่างจาก direct chat
* Notification จะไม่ถูกส่ง ถ้า user เปิดห้องอยู่

---

## 🧑‍💻 Development Tips

### ดู Redis keys

```bash
redis-cli
keys *
```

### ดู log

```bash
tail -f log/development.log
```

---

## 🏗 Architecture Overview

```
Client (Web / Mobile)
        │
        ▼
 Rails API (Controllers)
        │
        ├── PostgreSQL (Data)
        ├── Redis (Presence / Cache / State)
        └── ActionCable (Realtime WebSocket)
```

---

## 📌 Future Improvements

* [ ] Push Notification (FCM / APNs)
* [ ] Message reactions
* [ ] File upload (non-image)
* [ ] Read receipt per user (group chat)
* [ ] Horizontal scaling (Redis Pub/Sub cluster)

---

## 👨‍💻 Author

WPA Conference Backend System
