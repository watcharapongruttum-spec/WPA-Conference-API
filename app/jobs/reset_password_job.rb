class ResetPasswordJob < ApplicationJob
  queue_as :default

  def perform(delegate_id)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate

    frontend      = ENV.fetch("FRONTEND_URL", nil)
    token         = delegate.reset_password_token

    app_url       = "wpa://reset-password?token=#{token}"
    web_url       = "#{frontend}/deeplink-reset-password?token=#{token}"

    Rails.logger.info "=============================="
    Rails.logger.info "FRONTEND_URL=#{frontend}"
    Rails.logger.info "APP_URL=#{app_url}"
    Rails.logger.info "WEB_URL=#{web_url}"
    Rails.logger.info "=============================="

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="th">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: #f0f4f8;
            padding: 40px 16px;
          }

          .wrapper {
            max-width: 480px;
            margin: 0 auto;
          }

          .card {
            background: #ffffff;
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 4px 24px rgba(0,0,0,0.08);
          }

          /* Header */
          .header {
            background: #1a56db;
            padding: 32px 40px;
            text-align: center;
          }
          .header h1 {
            color: white;
            font-size: 22px;
            font-weight: 700;
            letter-spacing: 0.5px;
          }
          .header p {
            color: rgba(255,255,255,0.8);
            font-size: 13px;
            margin-top: 4px;
          }

          /* Body */
          .body {
            padding: 36px 40px;
          }
          .greeting {
            font-size: 16px;
            color: #111827;
            margin-bottom: 12px;
          }
          .description {
            font-size: 14px;
            color: #6b7280;
            line-height: 1.7;
            margin-bottom: 32px;
          }

          /* Divider */
          .divider {
            display: flex;
            align-items: center;
            gap: 12px;
            margin: 20px 0;
          }
          .divider-line {
            flex: 1;
            height: 1px;
            background: #e5e7eb;
          }
          .divider-text {
            font-size: 12px;
            color: #9ca3af;
            white-space: nowrap;
          }

          /* Buttons */
          .btn {
            display: block;
            width: 100%;
            padding: 14px;
            border-radius: 10px;
            text-align: center;
            text-decoration: none;
            font-size: 15px;
            font-weight: 600;
          }
          .btn-primary {
            background: #1a56db;
            color: #ffffff !important;
            margin-bottom: 0;
          }
          .btn-secondary {
            background: #f3f4f6;
            color: #374151 !important;
            border: 1px solid #e5e7eb;
          }

          /* Note */
          .note {
            margin-top: 28px;
            padding: 16px;
            background: #f9fafb;
            border-radius: 8px;
            border-left: 3px solid #1a56db;
          }
          .note p {
            font-size: 12px;
            color: #6b7280;
            line-height: 1.6;
          }
          .note strong {
            color: #374151;
          }

          /* Footer */
          .footer {
            padding: 20px 40px;
            border-top: 1px solid #f3f4f6;
            text-align: center;
          }
          .footer p {
            font-size: 12px;
            color: #9ca3af;
            line-height: 1.6;
          }
        </style>
      </head>
      <body>
        <div class="wrapper">
          <div class="card">

            <!-- Header -->
            <div class="header">
              <h1>WPA Conference</h1>
              <p>World Packaging Association</p>
            </div>

            <!-- Body -->
            <div class="body">
              <p class="greeting">สวัสดีคุณ #{delegate.name},</p>
              <p class="description">
                เราได้รับคำขอรีเซ็ตรหัสผ่านสำหรับบัญชีของคุณ<br>
                กรุณาเลือกวิธีที่ต้องการด้านล่าง ลิงก์นี้จะหมดอายุใน <strong>30 นาที</strong>
              </p>
              <!-- ✅ FIX #6: แก้จาก "1 ชั่วโมง" → "30 นาที"
                   ให้ตรงกับ delegate.rb reset_token_valid? ที่เช็ค 30.minutes.ago -->

              <!-- ปุ่ม 1: เปิดแอพ -->
              <a href="#{app_url}" class="btn btn-primary">
                📱 &nbsp;เปิดในแอพ WPA
              </a>

              <div class="divider">
                <div class="divider-line"></div>
                <div class="divider-text">หรือถ้าแอพไม่เปิด</div>
                <div class="divider-line"></div>
              </div>

              <!-- ปุ่ม 2: รีเซ็ตผ่านเว็บ -->
              <a href="#{web_url}" class="btn btn-secondary">
                🌐 &nbsp;รีเซ็ตรหัสผ่านผ่านเว็บ
              </a>

              <!-- Note -->
              <div class="note">
                <p>
                  ⚠️ <strong>หากคุณไม่ได้ขอรีเซ็ตรหัสผ่าน</strong><br>
                  กรุณาเพิกเฉยต่ออีเมลนี้ รหัสผ่านของคุณจะไม่ถูกเปลี่ยนแปลง
                </p>
              </div>
            </div>

            <!-- Footer -->
            <div class="footer">
              <p>
                อีเมลนี้ถูกส่งโดยอัตโนมัติ กรุณาอย่าตอบกลับ<br>
                © #{Time.current.year} WPA Conference. All rights reserved.
              </p>
            </div>

          </div>
        </div>
      </body>
      </html>
    HTML

    Rails.logger.info "HTML SIZE: #{html.length}"

    BrevoMailService.send_email(
      to: delegate.email,
      subject: "รีเซ็ตรหัสผ่าน — WPA Conference",
      html: html
    )
  end
end
