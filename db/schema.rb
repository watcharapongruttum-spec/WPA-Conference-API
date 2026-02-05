# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 202107270010001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "audits", force: :cascade do |t|
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.text "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_id", "associated_type"], name: "associated_index"
    t.index ["auditable_id", "auditable_type"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "booths", force: :cascade do |t|
    t.integer "reservation_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "branch_services", id: :serial, force: :cascade do |t|
    t.integer "service_id"
    t.integer "branch_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "is_active", default: true
    t.index ["branch_id"], name: "index_branch_services_on_branch_id"
    t.index ["service_id"], name: "index_branch_services_on_service_id"
  end

  create_table "branches", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.string "address1"
    t.string "state"
    t.string "postcode"
    t.string "tel"
    t.string "fax"
    t.string "weekday_from"
    t.string "weekday_to"
    t.string "weekend_from"
    t.string "weekend_to"
    t.string "email"
    t.string "emergency_number"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "address2"
    t.string "address3"
    t.integer "city_id"
    t.string "logo_file_name"
    t.string "logo_content_type"
    t.integer "logo_file_size"
    t.datetime "logo_updated_at", precision: nil
    t.string "website"
    t.integer "order_no", default: 0
    t.boolean "is_sent_top_ten_email"
    t.datetime "sent_top_ten_email_created_at", precision: nil
    t.boolean "is_sent_member_email"
    t.datetime "sent_member_email_created_at", precision: nil
    t.boolean "is_sent_quality_email"
    t.datetime "sent_quality_email_created_at", precision: nil
    t.string "newsletter_email"
    t.string "local_name"
    t.string "certificate_file_name"
    t.string "certificate_content_type"
    t.integer "certificate_file_size"
    t.datetime "certificate_updated_at", precision: nil
    t.boolean "status"
    t.integer "precaution_count"
    t.boolean "is_deleted", default: false
    t.datetime "deleted_at", precision: nil
    t.string "legal_name"
    t.string "trading_name"
    t.text "description"
    t.boolean "take_slot", default: true
  end

  create_table "chat_messages", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "recipient_id"
    t.text "content", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "room_id"
    t.bigint "chat_room_id"
    t.index ["chat_room_id"], name: "index_chat_messages_on_chat_room_id"
    t.index ["read_at"], name: "index_chat_messages_on_read_at"
    t.index ["recipient_id"], name: "index_chat_messages_on_recipient_id"
    t.index ["room_id"], name: "index_chat_messages_on_room_id"
    t.index ["sender_id", "recipient_id"], name: "index_chat_messages_on_sender_id_and_recipient_id"
    t.index ["sender_id"], name: "index_chat_messages_on_sender_id"
  end

  create_table "chat_rooms", force: :cascade do |t|
    t.string "title"
    t.integer "room_kind"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cities", id: :serial, force: :cascade do |t|
    t.integer "country_id"
    t.string "name"
    t.float "discount", default: 0.0
    t.integer "slot_available", default: 0
    t.integer "slot_taken", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "is_hidden", default: false
    t.index ["country_id"], name: "index_cities_on_country_id"
  end

  create_table "ckeditor_assets", id: :serial, force: :cascade do |t|
    t.string "data_file_name", null: false
    t.string "data_content_type"
    t.integer "data_file_size"
    t.integer "assetable_id"
    t.string "assetable_type", limit: 30
    t.string "type", limit: 30
    t.integer "width"
    t.integer "height"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["assetable_type", "assetable_id"], name: "idx_ckeditor_assetable"
    t.index ["assetable_type", "type", "assetable_id"], name: "idx_ckeditor_assetable_type"
  end

  create_table "comments", id: :serial, force: :cascade do |t|
    t.string "title", limit: 50, default: ""
    t.text "comment"
    t.integer "commentable_id"
    t.string "commentable_type"
    t.integer "user_id"
    t.string "role", default: "comments"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "current_url"
    t.string "current_object"
    t.string "username"
    t.inet "current_ip"
    t.string "level"
    t.string "action_code"
    t.string "commentable_label"
    t.string "previous_commentable_label"
    t.integer "member_id"
    t.string "member_name"
    t.string "previous_member_name"
    t.string "record_changes"
    t.string "extra_message"
    t.index ["commentable_id"], name: "index_comments_on_commentable_id"
    t.index ["commentable_type"], name: "index_comments_on_commentable_type"
    t.index ["member_id"], name: "index_comments_on_member_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "name"
    t.string "country"
    t.string "logo_file_name"
    t.string "logo_content_type"
    t.bigint "logo_file_size"
    t.datetime "logo_updated_at", precision: nil
    t.text "restrict_countries"
    t.string "login_token"
    t.integer "member_id"
    t.boolean "active", default: false
    t.boolean "admin", default: false
    t.text "restrict_companies"
    t.integer "branch_id"
    t.index ["email"], name: "index_companies_on_email", unique: true
    t.index ["reset_password_token"], name: "index_companies_on_reset_password_token", unique: true
  end

  create_table "conference_dates", force: :cascade do |t|
    t.bigint "conference_id"
    t.date "on_date"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["conference_id"], name: "index_conference_dates_on_conference_id"
  end

  create_table "conference_invoice_items", force: :cascade do |t|
    t.integer "invoiceable_id"
    t.string "invoiceable_type"
    t.string "code"
    t.text "description"
    t.float "amount"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "invoice_id"
    t.index ["invoice_id"], name: "index_conference_invoice_items_on_invoice_id"
  end

  create_table "conference_invoices", force: :cascade do |t|
    t.bigint "reservation_id"
    t.string "invoice_no"
    t.date "invoice_date"
    t.date "paid_date"
    t.string "status", default: "New"
    t.text "billing_address"
    t.float "total_fee", default: 0.0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.bigint "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.index ["reservation_id"], name: "index_conference_invoices_on_reservation_id"
  end

  create_table "conference_schedules", force: :cascade do |t|
    t.bigint "conference_date_id"
    t.string "title"
    t.datetime "start_at", precision: nil
    t.datetime "end_at", precision: nil
    t.boolean "allow_booking", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["conference_date_id"], name: "index_conference_schedules_on_conference_date_id"
  end

  create_table "conferences", force: :cascade do |t|
    t.string "name"
    t.boolean "is_current", default: false
    t.integer "slot_in_minute", default: 30
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "maximum_table_number", default: 10
    t.datetime "reservation_open", precision: nil
    t.datetime "reservation_close", precision: nil
    t.float "fee_booth", default: 0.0
    t.float "fee_delegate1", default: 0.0
    t.float "fee_delegate1_spouse", default: 0.0
    t.float "fee_delegate2", default: 0.0
    t.float "fee_delegate2_spouse", default: 0.0
    t.float "fee_delegate3", default: 0.0
    t.float "fee_delegate3_spouse", default: 0.0
    t.boolean "dynamic_table", default: false
    t.string "conference_year"
    t.datetime "scheduler_open", precision: nil
    t.datetime "scheduler_close", precision: nil
    t.boolean "enable_scheduler"
  end

  create_table "connection_requests", force: :cascade do |t|
    t.bigint "requester_id", null: false
    t.bigint "target_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requester_id", "target_id"], name: "index_connection_requests_on_pair", unique: true
    t.index ["requester_id"], name: "index_connection_requests_on_requester_id"
    t.index ["status"], name: "index_connection_requests_on_status"
    t.index ["target_id"], name: "index_connection_requests_on_target_id"
  end

  create_table "connections", force: :cascade do |t|
    t.bigint "requester_id", null: false
    t.bigint "target_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requester_id", "target_id"], name: "index_connections_on_requester_id_and_target_id", unique: true
    t.index ["status"], name: "index_connections_on_status"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.integer "contactable_id"
    t.string "contactable_type"
    t.string "title"
    t.string "name"
    t.string "job_title"
    t.string "email"
    t.string "cell_number"
    t.string "skype"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "allow_login"
    t.index ["email"], name: "index_contacts_on_email"
  end

  create_table "continents", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "countries", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "continent_id"
    t.string "code"
    t.string "calling_code", default: ""
    t.string "region"
    t.string "subregion"
  end

  create_table "delegates", force: :cascade do |t|
    t.bigint "company_id"
    t.string "name"
    t.string "title"
    t.string "email"
    t.string "phone"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "team_id"
    t.string "avatar_file_name"
    t.string "avatar_content_type"
    t.integer "avatar_file_size"
    t.datetime "avatar_updated_at", precision: nil
    t.integer "position"
    t.integer "reservation_id"
    t.boolean "first_conference", default: false
    t.boolean "spouse_attending", default: false
    t.string "spouse_name"
    t.boolean "need_room", default: false
    t.integer "branch_id"
    t.string "booking_no"
    t.string "password_digest"
    t.boolean "has_logged_in", default: false
    t.datetime "first_login_at"
    t.index ["branch_id"], name: "index_delegates_on_branch_id"
    t.index ["company_id"], name: "index_delegates_on_company_id"
    t.index ["email"], name: "index_delegates_on_email"
  end

  create_table "ex_members", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.date "date_of_leaving"
    t.text "reason_for_leaving"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "company_name"
    t.string "country"
    t.index ["member_id"], name: "index_ex_members_on_member_id"
  end

  create_table "headquarters", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.string "legal_name"
    t.string "trading_name"
    t.text "address1"
    t.string "city"
    t.string "state"
    t.string "postcode"
    t.string "tel"
    t.string "fax"
    t.string "email"
    t.string "website"
    t.integer "year_started"
    t.integer "employee_number"
    t.string "gmt_time"
    t.string "emergency_number"
    t.boolean "locally_owned", default: true
    t.string "locally_explain"
    t.boolean "comprehensive", default: false
    t.string "coverage_in"
    t.boolean "coverage_or_omissions", default: false
    t.text "licenses"
    t.string "fmc_license_number"
    t.string "fiata_license_number"
    t.string "iata_license_number"
    t.string "tax_id_number"
    t.string "memberships"
    t.integer "branch_number"
    t.text "description"
    t.float "air_export"
    t.float "ocean_export"
    t.float "import_and_brokerage"
    t.float "warehouse_and_logistics"
    t.float "other"
    t.float "total_annual"
    t.string "hear_from"
    t.string "specify_hear"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "notes"
    t.string "address2"
    t.index ["member_id"], name: "index_headquarters_on_member_id"
  end

  create_table "hotel_bookings", force: :cascade do |t|
    t.bigint "reservation_id"
    t.bigint "delegate_id"
    t.bigint "room_id"
    t.string "firstname"
    t.string "lastname"
    t.date "checkin_date"
    t.date "checkout_date"
    t.boolean "prepaid", default: true
    t.string "status", default: "New"
    t.boolean "smoke_option", default: false
    t.text "special_notes"
    t.string "hotel_ref"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "shared", default: false
    t.string "shared_firstname"
    t.string "shared_lastname"
    t.datetime "deleted_at", precision: nil
    t.index ["delegate_id"], name: "index_hotel_bookings_on_delegate_id"
    t.index ["reservation_id"], name: "index_hotel_bookings_on_reservation_id"
    t.index ["room_id"], name: "index_hotel_bookings_on_room_id"
  end

  create_table "hotel_change_requests", force: :cascade do |t|
    t.bigint "reservation_id"
    t.text "change_request"
    t.boolean "finished", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["reservation_id"], name: "index_hotel_change_requests_on_reservation_id"
  end

  create_table "hotels", force: :cascade do |t|
    t.string "name"
    t.text "address"
    t.text "description"
    t.boolean "active", default: true
    t.integer "quota", default: 0
    t.integer "taken", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "image_newsletters", id: :serial, force: :cascade do |t|
    t.string "image_file_name"
    t.string "image_content_type"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "invoice_items", id: :serial, force: :cascade do |t|
    t.text "description"
    t.decimal "amount"
    t.integer "invoice_id"
    t.integer "order_no", default: 0
    t.string "item_type"
  end

  create_table "invoice_sequences", id: :serial, force: :cascade do |t|
    t.string "invoice_type"
    t.integer "current_number"
    t.string "prefix"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "year", null: false
  end

  create_table "invoices", id: :serial, force: :cascade do |t|
    t.decimal "total"
    t.date "due_date"
    t.string "status"
    t.string "invoice_number"
    t.integer "member_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "street"
    t.string "city"
    t.string "country"
    t.string "postal"
    t.integer "membership_id"
    t.text "billing_address"
    t.date "invoice_date"
    t.integer "branch_id"
    t.integer "contact_id"
    t.date "start_date"
    t.date "end_date"
    t.string "pdf_file_name"
    t.string "pdf_content_type"
    t.integer "pdf_file_size"
    t.datetime "pdf_updated_at", precision: nil
    t.date "paid_at"
    t.string "fee_received_by"
    t.datetime "fee_received_at", precision: nil
    t.integer "invoice_sequence_id"
    t.decimal "total_bank_fees", default: "0.0"
    t.decimal "total_bank_fees_paid", default: "0.0"
    t.decimal "total_fees", default: "0.0"
    t.decimal "total_fees_paid", default: "0.0"
    t.decimal "total_discount", default: "0.0"
    t.decimal "total_discount_paid", default: "0.0"
    t.decimal "total_gold_fund", default: "0.0"
    t.integer "conference_reservation_id"
    t.string "conference_year"
    t.decimal "remain", default: "0.0"
    t.boolean "sent_paid_notification", default: false
    t.index ["invoice_sequence_id"], name: "index_invoices_on_invoice_sequence_id"
  end

  create_table "leave_forms", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.string "status"
    t.string "reason"
    t.text "explanation"
    t.bigint "reported_by_id"
    t.datetime "reported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "leave_type_id"
    t.index ["leave_type_id"], name: "index_leave_forms_on_leave_type_id"
    t.index ["reported_by_id"], name: "index_leave_forms_on_reported_by_id"
    t.index ["schedule_id"], name: "index_leave_forms_on_schedule_id"
    t.index ["status"], name: "index_leave_forms_on_status"
  end

  create_table "leave_types", force: :cascade do |t|
    t.string "code"
    t.string "name"
    t.text "description"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name_th"
    t.string "name_en"
    t.index ["code"], name: "index_leave_types_on_code", unique: true
  end

  create_table "login_sessions", id: :serial, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "auth_token"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.integer "current_member_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "access_code"
    t.index ["auth_token"], name: "index_login_sessions_on_auth_token"
    t.index ["email"], name: "index_login_sessions_on_email", unique: true
    t.index ["reset_password_token"], name: "index_login_sessions_on_reset_password_token", unique: true
  end

  create_table "member_attendances", force: :cascade do |t|
    t.bigint "member_id"
    t.integer "branch_id"
    t.string "default_text"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["member_id"], name: "index_member_attendances_on_member_id"
  end

  create_table "member_services", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.integer "service_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["member_id"], name: "index_member_services_on_member_id"
    t.index ["service_id"], name: "index_member_services_on_service_id"
  end

  create_table "member_submitted_news", id: :serial, force: :cascade do |t|
    t.integer "member_id", null: false
    t.boolean "attached_to_newsletter", default: false
    t.string "author", null: false
    t.string "email", null: false
    t.string "news_type", null: false
    t.string "subject", null: false
    t.text "content", null: false
    t.datetime "expiration_date", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "picture_file_name"
    t.string "picture_content_type"
    t.integer "picture_file_size"
    t.datetime "picture_updated_at", precision: nil
  end

  create_table "members", id: :serial, force: :cascade do |t|
    t.string "company_name"
    t.string "contact_name"
    t.string "contact_email"
    t.boolean "gold_fund_coverage", default: true
    t.integer "annual_fee", default: 0
    t.integer "incoming_transfer_fee", default: 0
    t.decimal "total_annual_fee", default: "0.0"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "website"
    t.string "logo_file_name"
    t.string "logo_content_type"
    t.integer "logo_file_size"
    t.datetime "logo_updated_at", precision: nil
    t.integer "country_id"
    t.boolean "is_approved", default: false
    t.datetime "application_created_at", precision: nil
    t.string "status"
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.string "sign_in_token"
    t.datetime "token_expire_at", precision: nil
    t.datetime "approved_date", precision: nil
    t.datetime "activated_at", precision: nil
    t.string "activated_by"
    t.boolean "is_validated"
    t.datetime "validated_at", precision: nil
    t.string "validated_by"
    t.datetime "terminated_at", precision: nil
    t.string "terminated_by"
    t.date "next_renewal_date"
    t.string "member_code"
    t.string "hear_from"
    t.string "specify_hear"
    t.boolean "is_founder"
    t.text "special_notes"
    t.text "shipping_notes"
    t.integer "precaution_count"
    t.index ["reset_password_token"], name: "index_members_on_reset_password_token", unique: true
    t.index ["sign_in_token"], name: "index_members_on_sign_in_token"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "recipient_id", null: false
    t.text "content", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["sender_id", "recipient_id"], name: "index_messages_on_sender_id_and_recipient_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "delegate_id", null: false
    t.string "notification_type", null: false
    t.string "notifiable_type"
    t.bigint "notifiable_id"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delegate_id"], name: "index_notifications_on_delegate_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["read_at"], name: "index_notifications_on_read_at"
  end

  create_table "on_holds", id: :serial, force: :cascade do |t|
    t.text "reason"
    t.date "date_of_hold"
    t.integer "member_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "payment_files", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "attachment"
    t.integer "member_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "payment_items", id: :serial, force: :cascade do |t|
    t.integer "invoice_id"
    t.string "description"
    t.decimal "amount"
    t.string "item_type"
    t.integer "order_no"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.date "pay_date"
    t.index ["invoice_id"], name: "index_payment_items_on_invoice_id"
  end

  create_table "precaution_gold_funds", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.text "reason"
    t.text "changed_by"
    t.datetime "changed_at", precision: nil
    t.integer "adjust"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "branch_id"
    t.index ["branch_id"], name: "index_precaution_gold_funds_on_branch_id"
    t.index ["member_id"], name: "index_precaution_gold_funds_on_member_id"
  end

  create_table "references", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.string "company_name"
    t.string "contact_name"
    t.string "email"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "is_approved", default: false
    t.string "status"
    t.datetime "approved_at", precision: nil
    t.string "approved_by"
    t.index ["member_id"], name: "index_references_on_member_id"
  end

  create_table "referral_members", id: :serial, force: :cascade do |t|
    t.integer "member_id"
    t.string "member_fname"
    t.string "member_lname"
    t.string "member_email"
    t.string "prospect_company"
    t.string "prospect_contact_fname"
    t.string "prospect_contact_lname"
    t.string "prospect_city"
    t.string "prospect_country"
    t.string "prospect_email"
    t.boolean "is_registered"
    t.datetime "sent_date", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["member_id"], name: "index_referral_members_on_member_id"
  end

  create_table "refinery_authentication_devise_roles", id: :serial, force: :cascade do |t|
    t.string "title"
  end

  create_table "refinery_authentication_devise_roles_users", id: false, force: :cascade do |t|
    t.integer "user_id"
    t.integer "role_id"
    t.index ["role_id", "user_id"], name: "refinery_roles_users_role_id_user_id"
    t.index ["user_id", "role_id"], name: "refinery_roles_users_user_id_role_id"
  end

  create_table "refinery_authentication_devise_user_plugins", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.string "name"
    t.integer "position"
    t.index ["name"], name: "index_refinery_authentication_devise_user_plugins_on_name"
    t.index ["user_id", "name"], name: "refinery_user_plugins_user_id_name", unique: true
  end

  create_table "refinery_authentication_devise_users", id: :serial, force: :cascade do |t|
    t.string "username", null: false
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "sign_in_count"
    t.datetime "remember_created_at", precision: nil
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "slug"
    t.string "full_name"
    t.index ["id"], name: "index_refinery_authentication_devise_users_on_id"
    t.index ["slug"], name: "index_refinery_authentication_devise_users_on_slug"
  end

  create_table "refinery_image_page_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_image_page_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "caption"
    t.index ["locale"], name: "index_refinery_image_page_translations_on_locale"
    t.index ["refinery_image_page_id"], name: "index_186c9a170a0ab319c675aa80880ce155d8f47244"
  end

  create_table "refinery_image_pages", id: :serial, force: :cascade do |t|
    t.integer "image_id"
    t.integer "page_id"
    t.integer "position"
    t.text "caption"
    t.string "page_type", default: "page"
    t.index ["image_id"], name: "index_refinery_image_pages_on_image_id"
    t.index ["page_id"], name: "index_refinery_image_pages_on_page_id"
  end

  create_table "refinery_image_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_image_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "image_alt"
    t.string "image_title"
    t.index ["locale"], name: "index_refinery_image_translations_on_locale"
    t.index ["refinery_image_id"], name: "index_refinery_image_translations_on_refinery_image_id"
  end

  create_table "refinery_images", id: :serial, force: :cascade do |t|
    t.string "image_mime_type"
    t.string "image_name"
    t.integer "image_size"
    t.integer "image_width"
    t.integer "image_height"
    t.string "image_uid"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "image_title"
    t.string "image_alt"
  end

  create_table "refinery_news_item_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_news_item_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "title"
    t.text "body"
    t.string "source"
    t.string "slug"
    t.index ["locale"], name: "index_refinery_news_item_translations_on_locale"
    t.index ["refinery_news_item_id"], name: "index_refinery_news_item_translations_fk"
  end

  create_table "refinery_news_items", id: :serial, force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.datetime "publish_date", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "image_id"
    t.datetime "expiration_date", precision: nil
    t.string "source"
    t.string "slug"
    t.integer "country_id"
    t.string "company_name"
    t.string "details"
    t.boolean "use_logo", default: false
    t.string "acronym"
    t.index ["id"], name: "index_refinery_news_items_on_id"
  end

  create_table "refinery_newsletters", id: :serial, force: :cascade do |t|
    t.string "subject"
    t.datetime "sent_at", precision: nil
    t.text "raw_content"
    t.string "mailchimp_list_uid"
    t.string "status"
    t.integer "position"
    t.string "mailchimp_campaign_uid"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "refinery_newsletters_recipients", id: :serial, force: :cascade do |t|
    t.string "email"
    t.string "recipient_type"
    t.integer "position"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "refinery_page_part_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_page_part_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "body"
    t.index ["locale"], name: "index_refinery_page_part_translations_on_locale"
    t.index ["refinery_page_part_id"], name: "index_refinery_page_part_translations_on_refinery_page_part_id"
  end

  create_table "refinery_page_parts", id: :serial, force: :cascade do |t|
    t.integer "refinery_page_id"
    t.string "slug"
    t.text "body"
    t.integer "position"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "title"
    t.index ["id"], name: "index_refinery_page_parts_on_id"
    t.index ["refinery_page_id"], name: "index_refinery_page_parts_on_refinery_page_id"
  end

  create_table "refinery_page_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_page_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "title"
    t.string "custom_slug"
    t.string "menu_title"
    t.string "slug"
    t.index ["locale"], name: "index_refinery_page_translations_on_locale"
    t.index ["refinery_page_id"], name: "index_refinery_page_translations_on_refinery_page_id"
  end

  create_table "refinery_pages", id: :serial, force: :cascade do |t|
    t.integer "parent_id"
    t.string "path"
    t.string "slug"
    t.string "custom_slug"
    t.boolean "show_in_menu", default: true
    t.string "link_url"
    t.string "menu_match"
    t.boolean "deletable", default: true
    t.boolean "draft", default: false
    t.boolean "skip_to_first_child", default: false
    t.integer "lft"
    t.integer "rgt"
    t.integer "depth"
    t.string "view_template"
    t.string "layout_template"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "background_image_id"
    t.boolean "member_only", default: false
    t.index ["depth"], name: "index_refinery_pages_on_depth"
    t.index ["id"], name: "index_refinery_pages_on_id"
    t.index ["lft"], name: "index_refinery_pages_on_lft"
    t.index ["parent_id"], name: "index_refinery_pages_on_parent_id"
    t.index ["rgt"], name: "index_refinery_pages_on_rgt"
  end

  create_table "refinery_resource_translations", id: :serial, force: :cascade do |t|
    t.integer "refinery_resource_id", null: false
    t.string "locale", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "resource_title"
    t.index ["locale"], name: "index_refinery_resource_translations_on_locale"
    t.index ["refinery_resource_id"], name: "index_refinery_resource_translations_on_refinery_resource_id"
  end

  create_table "refinery_resources", id: :serial, force: :cascade do |t|
    t.string "file_mime_type"
    t.string "file_name"
    t.integer "file_size"
    t.string "file_uid"
    t.string "file_ext"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "refinery_settings", id: :serial, force: :cascade do |t|
    t.string "name"
    t.text "value"
    t.boolean "destroyable", default: true
    t.string "scoping"
    t.boolean "restricted", default: false
    t.string "form_value_type"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "slug"
    t.string "title"
    t.index ["name"], name: "index_refinery_settings_on_name"
  end

  create_table "register_tokens", id: :serial, force: :cascade do |t|
    t.string "email"
    t.string "token"
    t.boolean "is_used", default: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["email"], name: "index_register_tokens_on_email"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "company_id"
    t.bigint "conference_id"
    t.bigint "member_id"
    t.datetime "reserved_at", precision: nil
    t.string "status", default: "New"
    t.string "conference_email"
    t.float "total_fee", default: 0.0
    t.string "slug"
    t.boolean "no_booking", default: false
    t.boolean "invoiced", default: false
    t.string "invoice_number"
    t.integer "branch_id"
    t.string "company_name"
    t.boolean "notification_sent", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["company_id"], name: "index_reservations_on_company_id"
    t.index ["conference_id"], name: "index_reservations_on_conference_id"
    t.index ["member_id"], name: "index_reservations_on_member_id"
  end

  create_table "room_members", force: :cascade do |t|
    t.bigint "chat_room_id", null: false
    t.bigint "delegate_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role"
    t.index ["chat_room_id"], name: "index_room_members_on_chat_room_id"
    t.index ["delegate_id"], name: "index_room_members_on_delegate_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.bigint "conference_id"
    t.bigint "hotel_id"
    t.string "title"
    t.text "description"
    t.float "price", default: 0.0
    t.boolean "allow_extra_bed", default: false
    t.float "extra_bed_cost", default: 0.0
    t.text "extra_bed_info"
    t.boolean "prepaid_only", default: false
    t.integer "display_order", default: 99
    t.boolean "active", default: true
    t.float "prepaid_price"
    t.float "shared_price"
    t.float "prepaid_shared_price"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "room_kind", null: false
    t.index ["conference_id"], name: "index_rooms_on_conference_id"
    t.index ["hotel_id"], name: "index_rooms_on_hotel_id"
  end

  create_table "schedules", force: :cascade do |t|
    t.bigint "conference_date_id"
    t.integer "target_id"
    t.integer "booker_id"
    t.datetime "start_at", precision: nil
    t.datetime "end_at", precision: nil
    t.string "table_number"
    t.string "country"
    t.boolean "is_static_table", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["booker_id"], name: "index_schedules_on_booker_id"
    t.index ["conference_date_id"], name: "index_schedules_on_conference_date_id"
    t.index ["end_at"], name: "index_schedules_on_end_at"
    t.index ["start_at"], name: "index_schedules_on_start_at"
  end

  create_table "seo_meta", id: :serial, force: :cascade do |t|
    t.integer "seo_meta_id"
    t.string "seo_meta_type"
    t.string "browser_title"
    t.text "meta_description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["id"], name: "index_seo_meta_on_id"
    t.index ["seo_meta_id", "seo_meta_type"], name: "id_type_index_on_seo_meta"
  end

  create_table "services", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "is_freight", default: false
  end

  create_table "sessions", id: :serial, force: :cascade do |t|
    t.string "session_id", null: false
    t.text "data"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "settings", id: :serial, force: :cascade do |t|
    t.string "var", null: false
    t.text "value"
    t.integer "thing_id"
    t.string "thing_type", limit: 30
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["thing_type", "thing_id", "var"], name: "index_settings_on_thing_type_and_thing_id_and_var", unique: true
  end

  create_table "settings_conference", force: :cascade do |t|
    t.string "var", null: false
    t.text "value"
    t.integer "thing_id"
    t.string "thing_type", limit: 30
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["thing_type", "thing_id", "var"], name: "index_settings_conference_on_thing_type_and_thing_id_and_var", unique: true
  end

  create_table "sponsors", force: :cascade do |t|
    t.bigint "sponsorship_id"
    t.bigint "reservation_id"
    t.boolean "show", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["reservation_id"], name: "index_sponsors_on_reservation_id"
    t.index ["sponsorship_id"], name: "index_sponsors_on_sponsorship_id"
  end

  create_table "sponsorships", force: :cascade do |t|
    t.bigint "conference_id"
    t.string "title"
    t.integer "available", default: 0
    t.string "quota"
    t.text "description"
    t.float "fee", default: 0.0
    t.integer "free_room_id"
    t.integer "free_conf_fee", default: 0
    t.integer "free_booth", default: 0
    t.integer "free_room_count", default: 0
    t.integer "free_room_nights", default: 0
    t.integer "display_order", default: 99
    t.boolean "active", default: true
    t.date "created_date"
    t.date "expired_date"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "logo_file_name"
    t.string "logo_content_type"
    t.bigint "logo_file_size"
    t.datetime "logo_updated_at", precision: nil
    t.index ["conference_id"], name: "index_sponsorships_on_conference_id"
  end

  create_table "spouses", force: :cascade do |t|
    t.bigint "delegate_id"
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["delegate_id"], name: "index_spouses_on_delegate_id"
  end

  create_table "surveys", force: :cascade do |t|
    t.bigint "company_id"
    t.string "company_name"
    t.integer "overall_rating"
    t.text "countries_wanted"
    t.text "priorities"
    t.float "percent_wpa"
    t.integer "overall_sales"
    t.integer "overall_comm"
    t.integer "overall_ops"
    t.float "annual_rev"
    t.float "air_shipments"
    t.float "ocean_shipments"
    t.float "number_staff"
    t.string "best_communications"
    t.string "best_sales"
    t.string "best_operations"
    t.string "vote_middle_east_africa"
    t.string "vote_america"
    t.string "vote_asia_oceania"
    t.string "vote_europe"
    t.string "vote_indian_subcont"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["company_id"], name: "index_surveys_on_company_id"
  end

  create_table "tables", force: :cascade do |t|
    t.bigint "conference_id"
    t.string "table_number"
    t.text "adjacent_tables"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["conference_id"], name: "index_tables_on_conference_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.integer "taggable_id"
    t.string "taggable_type"
    t.integer "tagger_id"
    t.string "tagger_type"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.bigint "company_id"
    t.bigint "table_id"
    t.string "name"
    t.string "country_code"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "branch_id"
    t.index ["branch_id"], name: "index_teams_on_branch_id"
    t.index ["company_id"], name: "index_teams_on_company_id"
    t.index ["table_id"], name: "index_teams_on_table_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "branch_services", "branches"
  add_foreign_key "branch_services", "services"
  add_foreign_key "chat_messages", "chat_rooms"
  add_foreign_key "chat_messages", "delegates", column: "recipient_id"
  add_foreign_key "chat_messages", "delegates", column: "sender_id"
  add_foreign_key "chat_messages", "rooms"
  add_foreign_key "connection_requests", "delegates", column: "requester_id"
  add_foreign_key "connection_requests", "delegates", column: "target_id"
  add_foreign_key "connections", "delegates", column: "requester_id"
  add_foreign_key "connections", "delegates", column: "target_id"
  add_foreign_key "invoices", "invoice_sequences"
  add_foreign_key "leave_forms", "delegates", column: "reported_by_id"
  add_foreign_key "leave_forms", "leave_types"
  add_foreign_key "leave_forms", "schedules"
  add_foreign_key "member_services", "members"
  add_foreign_key "member_services", "services"
  add_foreign_key "messages", "delegates", column: "recipient_id"
  add_foreign_key "messages", "delegates", column: "sender_id"
  add_foreign_key "notifications", "delegates"
  add_foreign_key "payment_items", "invoices"
  add_foreign_key "precaution_gold_funds", "branches"
  add_foreign_key "precaution_gold_funds", "members"
  add_foreign_key "referral_members", "members"
  add_foreign_key "room_members", "chat_rooms"
  add_foreign_key "room_members", "delegates"
end
