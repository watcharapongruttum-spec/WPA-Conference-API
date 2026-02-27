RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # ✅ เปิด focus mode
  config.filter_run_when_matching :focus

  # ✅ บันทึกสถานะ test เพื่อใช้ --only-failures
  config.example_status_persistence_file_path = "spec/examples.txt"

  # ✅ ปิด monkey patching (Best practice)
  config.disable_monkey_patching!

  # ✅ ถ้ารันไฟล์เดียว ให้ใช้ doc formatter
  config.default_formatter = "doc" if config.files_to_run.one?

  # ✅ แสดง 10 test ที่ช้าที่สุด
  config.profile_examples = 10

  # ✅ รันแบบ random ป้องกัน order dependency bug
  config.order = :random

  # ✅ ทำให้ seed reproducible
  Kernel.srand config.seed
end
