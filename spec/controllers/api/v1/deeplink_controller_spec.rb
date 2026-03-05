# spec/controllers/api/v1/deeplink_controller_spec.rb
require "rails_helper"

RSpec.describe Api::V1::DeeplinkController, type: :controller do
  let(:delegate) { create(:delegate) }

  before do
    delegate.generate_reset_token!
  end

  # -------------------------------------------------------
  # บัค #9: XSS ใน error block
  # -------------------------------------------------------
  describe "POST #reset_password_submit — XSS prevention" do
    it "escapes HTML in error messages" do
      post :reset_password_submit, params: {
        token: delegate.reset_password_token,
        password: "<script>alert(1)</script>",
        password_confirmation: "different"
      }

      # script tag ต้องถูก escape
      expect(response.body).not_to include("<script>")
      expect(response.body).to include("&lt;script&gt;").or include("Password confirmation does not match")
    end

    it "escapes special HTML characters in token field" do
      post :reset_password_submit, params: {
        token: '"><script>alert(1)</script>',
        password: "Password1",
        password_confirmation: "Password1"
      }

      expect(response.body).not_to include('"><script>')
    end
  end


  describe "GET #reset_password — expired token" do
    it "shows 30 minutes expiry message (not 1 hour)" do
      # ทำให้ token หมดอายุ (> 30 นาที)
      delegate.update!(reset_password_sent_at: 31.minutes.ago)

      get :reset_password, params: { token: delegate.reset_password_token }

      expect(response.body).to include("30 นาที")
    end
  end

  describe "GET #reset_password — valid flow" do
    it "shows form for valid token" do
      get :reset_password, params: { token: delegate.reset_password_token }
      expect(response.body).to include("ตั้งรหัสผ่านใหม่")
    end

    it "shows invalid page for missing token" do
      get :reset_password, params: { token: "" }
      expect(response.body).to include("ลิงก์ไม่ถูกต้อง")
    end

    it "shows invalid page for wrong token" do
      get :reset_password, params: { token: "wrongtoken123" }
      expect(response.body).to include("ลิงก์ไม่ถูกต้อง")
    end
  end

  describe "POST #reset_password_submit — success" do
    it "changes password and clears token" do
      post :reset_password_submit, params: {
        token: delegate.reset_password_token,
        password: "NewPass1",
        password_confirmation: "NewPass1"
      }

      delegate.reload
      expect(delegate.reset_password_token).to be_nil
      expect(delegate.authenticate("NewPass1")).to be_truthy
      expect(response.body).to include("เปลี่ยนรหัสผ่านสำเร็จ")
    end

    it "rejects password without number" do
      post :reset_password_submit, params: {
        token: delegate.reset_password_token,
        password: "NoNumber",
        password_confirmation: "NoNumber"
      }

      expect(response.body).to include("number")
    end

    it "rejects short password" do
      post :reset_password_submit, params: {
        token: delegate.reset_password_token,
        password: "Ab1",
        password_confirmation: "Ab1"
      }

      expect(response.body).to include("8 characters")
    end
  end
end
