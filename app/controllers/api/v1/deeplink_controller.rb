module Api
  module V1
    class DeeplinkController < ApplicationController
      skip_before_action :authenticate_delegate!

      def reset_password
        @token = params[:token]

        return render html: build_page(:invalid), layout: false if @token.blank?

        @delegate = Delegate.find_by(reset_password_token: @token)

        return render html: build_page(:invalid), layout: false unless @delegate

        return render html: build_page(:expired), layout: false unless @delegate.reset_token_valid?

        render html: build_page(:form, token: @token), layout: false
      end

      def reset_password_submit
        token    = params[:token]
        password = params[:password]
        confirm  = params[:password_confirmation]

        delegate = Delegate.find_by(reset_password_token: token)

        error = validate(delegate, token, password, confirm)
        return render html: build_page(:form, token: token, error: error), layout: false if error

        ActiveRecord::Base.transaction do
          delegate.update!(
            password: password,
            password_confirmation: password
          )
          delegate.clear_reset_token!

          SecurityLog.create!(
            delegate: delegate,
            event: "reset_password_success",
            ip: request.remote_ip
          )
        end

        render html: build_page(:success), layout: false
      rescue ActiveRecord::RecordInvalid => e
        render html: build_page(:form, token: token, error: e.message), layout: false
      end

      private

      def validate(delegate, _token, password, confirm)
        return "Invalid or expired token" unless delegate&.reset_token_valid?
        return "Password is required" if password.blank?
        return "Password must be at least 8 characters" if password.length < 8
        return "Password must contain at least one number" unless password.match?(/[0-9]/)
        return "Password confirmation does not match" if password != confirm

        nil
      end

      def build_page(state, token: nil, error: nil)
        content = case state
                  when :form    then form_html(token, error)
                  when :success then success_html
                  when :expired then expired_html
                  when :invalid then invalid_html
                  end

        wrap_html(content).html_safe
      end

      def wrap_html(content)
        <<~HTML
          <!DOCTYPE html>
          <html lang="th">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Reset Password — WPA Conference</title>
            <style>
              * { box-sizing: border-box; margin: 0; padding: 0; }
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                background: #f0f4f8;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
              }
              .card {
                background: white;
                border-radius: 16px;
                padding: 40px;
                width: 100%;
                max-width: 420px;
                box-shadow: 0 4px 24px rgba(0,0,0,0.08);
              }
              .logo { text-align: center; font-size: 22px; font-weight: 700; color: #1a56db; margin-bottom: 8px; }
              .subtitle { text-align: center; color: #6b7280; font-size: 14px; margin-bottom: 32px; }
              h2 { font-size: 20px; color: #111827; margin-bottom: 24px; text-align: center; }
              label { display: block; font-size: 14px; font-weight: 500; color: #374151; margin-bottom: 6px; }
              input[type="password"] {
                width: 100%; padding: 12px 16px; border: 1.5px solid #d1d5db;
                border-radius: 8px; font-size: 15px; outline: none;
                transition: border-color 0.2s; margin-bottom: 16px;
              }
              input[type="password"]:focus { border-color: #1a56db; }
              button[type="submit"] {
                width: 100%; padding: 13px; background: #1a56db; color: white;
                border: none; border-radius: 8px; font-size: 16px; font-weight: 600;
                cursor: pointer; transition: background 0.2s;
              }
              button[type="submit"]:hover { background: #1648c0; }
              .error-box {
                background: #fef2f2; border: 1px solid #fecaca; color: #dc2626;
                padding: 12px 16px; border-radius: 8px; font-size: 14px; margin-bottom: 20px;
              }
              .hint { font-size: 12px; color: #9ca3af; margin-top: -10px; margin-bottom: 16px; }
              .icon { text-align: center; font-size: 48px; margin-bottom: 16px; }
              .message { text-align: center; color: #374151; font-size: 15px; line-height: 1.6; }
              .open-app-btn {
                display: block; margin-top: 24px; text-align: center; padding: 12px;
                background: #f3f4f6; border-radius: 8px; color: #1a56db;
                font-weight: 600; text-decoration: none; font-size: 15px;
              }
            </style>
          </head>
          <body>
            <div class="card">
              <div class="logo">WPA Conference</div>
              <div class="subtitle">World Packaging Association</div>
              #{content}
            </div>
          </body>
          </html>
        HTML
      end

      def form_html(token, error)
        # ✅ FIX: escape error เพื่อป้องกัน XSS
        error_block = error ? "<div class='error-box'>#{CGI.escapeHTML(error.to_s)}</div>" : ""

        <<~HTML
          <h2>ตั้งรหัสผ่านใหม่</h2>
          #{error_block}
          <form method="POST" action="/api/v1/deeplink/reset_password_submit">
            <input type="hidden" name="token" value="#{CGI.escapeHTML(token.to_s)}">
            <input type="hidden" name="authenticity_token" value="#{begin
              form_authenticity_token
            rescue StandardError
              ''
            end}">

            <label>รหัสผ่านใหม่</label>
            <input type="password" name="password" placeholder="อย่างน้อย 8 ตัว" required>
            <div class="hint">ต้องมีตัวเลขอย่างน้อย 1 ตัว</div>

            <label>ยืนยันรหัสผ่าน</label>
            <input type="password" name="password_confirmation" placeholder="กรอกซ้ำอีกครั้ง" required>

            <button type="submit">เปลี่ยนรหัสผ่าน</button>
          </form>
        HTML
      end

      def success_html
        app_url = "wpa://reset-success"

        <<~HTML
          <div class="icon">✅</div>
          <h2>เปลี่ยนรหัสผ่านสำเร็จ</h2>
          <p class="message">รหัสผ่านของคุณถูกเปลี่ยนแล้ว<br>กลับไปเข้าสู่ระบบในแอพได้เลย</p>
          <a href="#{app_url}" class="open-app-btn">เปิดแอพ WPA</a>
          <script>
            setTimeout(function() { window.location = "#{app_url}"; }, 1500);
          </script>
        HTML
      end

      def expired_html
        # ✅ FIX: แก้ข้อความให้ตรงกับ delegate.rb ที่ expire จริงๆ 30 นาที
        <<~HTML
          <div class="icon">⏰</div>
          <h2>ลิงก์หมดอายุแล้ว</h2>
          <p class="message">
            ลิงก์นี้ใช้งานได้ภายใน 30 นาทีหลังจากขอ<br>
            กรุณาขอลิงก์ใหม่อีกครั้งในแอพ
          </p>
        HTML
      end

      def invalid_html
        <<~HTML
          <div class="icon">❌</div>
          <h2>ลิงก์ไม่ถูกต้อง</h2>
          <p class="message">
            ลิงก์นี้ไม่ถูกต้องหรือถูกใช้ไปแล้ว<br>
            กรุณาขอลิงก์ใหม่อีกครั้งในแอพ
          </p>
        HTML
      end
    end
  end
end
