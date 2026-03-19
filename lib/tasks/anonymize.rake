# lib/tasks/anonymize.rake
#
# วิธีใช้:
#   bundle exec rake db:anonymize           ← มี prompt ถามก่อน
#   bundle exec rake db:anonymize CONFIRM=yes  ← ข้าม prompt
#
# ต้องการ: gem 'faker' ใน Gemfile
#   gem 'faker'

namespace :db do
  desc "Anonymize personal/sensitive data with fake English data"
  task anonymize: :environment do

    # ── ยืนยันก่อนรัน ──────────────────────────────────────────
    unless ENV["CONFIRM"] == "yes"
      puts "\n⚠️  WARNING: This will overwrite real data with fake data."
      puts "   Run on a COPY of your database, NOT production!\n\n"
      print "   Type 'yes' to continue: "
      abort("❌ Aborted.") unless $stdin.gets.chomp == "yes"
    end

    require "faker"
    Faker::Config.locale = "en"

    # ── Helper: email ที่ไม่ซ้ำกัน 100% โดยใช้ id ของ record ──
    def fake_email(id, prefix = "user")
      "#{prefix}_#{id}@example-#{Faker::Alphanumeric.alphanumeric(number: 6)}.com"
    end

    # ── Helper: rescue ถ้า record นั้นพัง ข้ามไปทำ record ถัดไป
    def safe_update(record)
      yield record
    rescue => e
      puts "    ⚠️  skip id=#{record.id}: #{e.message.truncate(80)}"
    end

    puts "\n🔄 Anonymizing...\n\n"

    # ────────────────────────────────────────────────────────────
    # 1. COMPANIES
    # ────────────────────────────────────────────────────────────
    puts "  [1/5] companies"
    Company.find_each do |c|
      safe_update(c) do
        c.update_columns(
          name:                 Faker::Company.name,
          email:                fake_email(c.id, "company"),
          login_token:          nil,
          reset_password_token: nil,
          encrypted_password:   BCrypt::Password.create("12345678")
        )
      end
    end

    # ────────────────────────────────────────────────────────────
    # 2. DELEGATES
    # ────────────────────────────────────────────────────────────
    puts "  [2/5] delegates"
    Delegate.find_each do |d|
      safe_update(d) do
        d.update_columns(
          name:                 Faker::Name.name,
          email:                fake_email(d.id, "delegate"),
          phone:                Faker::PhoneNumber.cell_phone,
          spouse_name:          d.spouse_name.present? ? Faker::Name.name : nil,
          booking_no:           d.booking_no.present?  ? "BK-#{d.id}-#{Faker::Alphanumeric.alphanumeric(number: 6).upcase}" : nil,
          device_token:         nil,
          reset_password_token: nil,
          password_digest:      BCrypt::Password.create("12345678")
        )
      end
    end

    # ────────────────────────────────────────────────────────────
    # 3. RESERVATIONS
    # ────────────────────────────────────────────────────────────
    puts "  [3/5] reservations"
    Reservation.find_each do |r|
      safe_update(r) do
        r.update_columns(
          conference_email: fake_email(r.id, "conf"),
          company_name:     Faker::Company.name,
          invoice_number:   r.invoice_number.present? ? "INV-#{r.id}-#{Faker::Number.number(digits: 6)}" : nil
        )
      end
    end

    # ────────────────────────────────────────────────────────────
    # 4. CHAT MESSAGES
    # ────────────────────────────────────────────────────────────
    puts "  [4/5] chat_messages"
    ChatMessage.where(deleted_at: nil).find_each do |cm|
      safe_update(cm) { cm.update_columns(content: Faker::Lorem.sentence) }
    end

    # ────────────────────────────────────────────────────────────
    # 5. TEAMS
    # ────────────────────────────────────────────────────────────
    # คงรูปแบบ "Team N (City)" — counter reset ต่อ table
    # ทีมที่ไม่มี table_id → "Team (City)" ไม่มีเลข
    puts "  [5/5] teams"

    team_counter = Hash.new(0)
    Team.order(Arel.sql("table_id NULLS LAST"), :id).find_each do |t|
      safe_update(t) do
        city = Faker::Address.city
        name = if t.table_id
          team_counter[t.table_id] += 1
          "Team #{team_counter[t.table_id]} (#{city})"
        else
          "Team (#{city})"
        end
        t.update_columns(name: name)
      end
    end

    # ────────────────────────────────────────────────────────────
    # BULK UPDATE
    # ────────────────────────────────────────────────────────────
    puts "  [bulk] audit_logs"
    AuditLog.update_all(
      ip_address:     "0.0.0.0",
      user_agent:     "anonymized",
      record_changes: nil
    )

    puts "  [bulk] security_logs"
    SecurityLog.update_all(ip: "0.0.0.0")

    puts "\n✅ Done!"
    puts "   All passwords reset to: 12345678"
    puts "   All tokens & sessions cleared.\n\n"
  end
end
