# app/services/time_formatter.rb
module TimeFormatter
  TIMEZONE = 'Asia/Bangkok'.freeze

  # แปลง timestamp เดี่ยว
  def self.format(time)
    return nil unless time
    time.in_time_zone(TIMEZONE).iso8601
  end

  # แปลง hash ที่มี timestamp fields หลายตัวในทีเดียว
  def self.format_fields(hash, *fields)
    fields.each do |field|
      hash[field] = format(hash[field]) if hash.key?(field)
    end
    hash
  end
end