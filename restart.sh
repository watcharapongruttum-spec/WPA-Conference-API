#!/bin/bash

SESSION="app"

# ถ้ามี session เก่าอยู่แล้ว ให้ลบทิ้งก่อน
tmux kill-session -t $SESSION 2>/dev/null

# สร้าง session ใหม่ (pane แรก = Rails)
tmux new-session -d -s $SESSION "rails s -b 0.0.0.0 -p 3000"

# สร้าง pane ที่สอง (Sidekiq)
tmux split-window -h -t $SESSION "bundle exec sidekiq"

# จัด layout ให้สวย
tmux select-layout -t $SESSION even-horizontal

# เข้า session
tmux attach -t $SESSION