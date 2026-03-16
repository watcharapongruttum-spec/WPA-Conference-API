# lib/tasks/generate_schedule_2025.rake

namespace :schedule do
  desc "Generate schedule for 2025 - fill to capacity, distribute fairly"
  task generate_2025: :environment do
    YEAR = "2025"

    puts "🚀 Starting schedule generation for #{YEAR}..."

    conf = Conference.find_by(conference_year: YEAR)
    abort "❌ Conference #{YEAR} not found" unless conf

    scheduled_target_ids = Schedule
      .joins(conference_date: :conference)
      .where(conferences: { conference_year: YEAR })
      .where.not(target_id: nil)
      .pluck(:target_id).uniq

    teams = Team.where.not(id: scheduled_target_ids).includes(:delegates).to_a
    puts "📋 Teams to schedule: #{teams.count}"
    abort "✅ All teams already scheduled!" if teams.empty?

    tables = Table
               .where(conference: conf)
               .where("table_number ~ '^[0-9]+$'")
               .order(Arel.sql("table_number::integer"))
               .to_a

    total_created = 0

    conf.conference_dates.order(:on_date).each do |conf_date|
      puts "\n📅 #{conf_date.on_date}"

      slots = ConferenceSchedule
                .where(conference_date_id: conf_date.id, allow_booking: true)
                .order(:start_at)
                .pluck(:start_at, :end_at)

      if slots.empty?
        puts "  ⚠️  No bookable slots — skip"
        next
      end

      capacity = slots.count * tables.count
      puts "  Slots: #{slots.count} | Tables: #{tables.count} | Capacity: #{capacity}"

      # track meetings per team today
      meetings_count = Hash.new(0)

      # mark existing bookings (skip nil table_id)
      slot_table_map = Hash.new { |h, k| h[k] = {} }
      Schedule.where(conference_date_id: conf_date.id)
              .where.not(table_id: nil)
              .pluck(:start_at, :table_id).each do |sa, tid|
        slot_table_map[sa][tid] = true
      end

      # shuffle pairs for fairness
      pairs = teams.combination(2).to_a.shuffle
      schedules_to_insert = []

      # max meetings per team per day = floor(capacity * 2 / teams.count)
      max_per_team = [(capacity * 2 / teams.count.to_f).floor, 1].max
      puts "  Max meetings/team/day: #{max_per_team}"

      pairs.each do |booker_team, target_team|
        next if meetings_count[booker_team.id] >= max_per_team
        next if meetings_count[target_team.id] >= max_per_team

        booker = booker_team.delegates.first
        next unless booker

        assigned = false
        slots.each do |start_at, end_at|
          tables.each do |table|
            next if slot_table_map[start_at][table.id]

            slot_table_map[start_at][table.id] = true
            meetings_count[booker_team.id] += 1
            meetings_count[target_team.id] += 1

            schedules_to_insert << {
              conference_date_id: conf_date.id,
              booker_id:          booker.id,
              target_id:          target_team.id,
              table_id:           table.id,
              table_number:       table.table_number,
              start_at:           start_at,
              end_at:             end_at,
              country:            booker_team.country_code || "",
              created_at:         Time.current,
              updated_at:         Time.current
            }

            assigned = true
            break
          end
          break if assigned
        end

        # stop if all slots filled
        break if slot_table_map.values.all? { |t| t.keys.count >= tables.count }
      end

      if schedules_to_insert.any?
        Schedule.insert_all(schedules_to_insert)
        total_created += schedules_to_insert.count
        puts "  ✅ Created: #{schedules_to_insert.count} schedules"

        covered = meetings_count.count { |_, v| v > 0 }
        puts "  Teams covered today: #{covered}/#{teams.count}"
      else
        puts "  ⚠️  No schedules created"
      end
    end

    puts "\n🎉 Done! Total created: #{total_created}"
  end

  desc "Preview capacity vs demand"
  task preview_2025: :environment do
    YEAR = "2025"
    conf = Conference.find_by(conference_year: YEAR)
    abort "❌ Conference not found" unless conf

    scheduled_target_ids = Schedule
      .joins(conference_date: :conference)
      .where(conferences: { conference_year: YEAR })
      .where.not(target_id: nil)
      .pluck(:target_id).uniq

    teams = Team.where.not(id: scheduled_target_ids)
    tables = Table.where(conference: conf).where("table_number ~ '^[0-9]+$'").count

    puts "\n=== Preview 2025 ==="
    puts "Teams to schedule: #{teams.count}"
    puts "Tables: #{tables}"
    puts ""

    conf.conference_dates.order(:on_date).each do |cd|
      slots = ConferenceSchedule.where(conference_date_id: cd.id, allow_booking: true).count
      capacity = slots * tables
      max_per_team = capacity > 0 ? [(capacity * 2 / teams.count.to_f).floor, 1].max : 0
      puts "#{cd.on_date} | slots: #{slots} | capacity: #{capacity} | max/team: #{max_per_team}"
    end
  end

  desc "Rollback generated 2025 schedules (skips those with leave_forms)"
  task rollback_2025: :environment do
    count = Schedule
              .joins(conference_date: :conference)
              .where(conferences: { conference_year: "2025" })
              .where.not(id: LeaveForm.select(:schedule_id))
              .delete_all
    puts "🗑  Deleted: #{count} schedules"
  end
end