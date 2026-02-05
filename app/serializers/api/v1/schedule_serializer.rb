module Api
  module V1
    class ScheduleSerializer < ActiveModel::Serializer
      attributes :id,
                 :start_at,
                 :end_at,
                 :table_number,
                 :country,
                 :conference_date,
                 :delegate,
                 :duration_minutes

      # -------------------------
      # วันที่ประชุม
      # -------------------------
      def conference_date
        object.conference_date&.on_date
      end

      # -------------------------
      # ระยะเวลา
      # -------------------------
      def duration_minutes
        return nil unless object.start_at && object.end_at
        ((object.end_at - object.start_at) / 60).to_i
      end

      # -------------------------
      # คนที่เรานัดด้วย
      # -------------------------
      def delegate
        current_user = scope

        other_delegate =
          if current_user && object.booker_id == current_user.id
            object.target
          else
            object.booker
          end

        return unknown_delegate unless other_delegate

        {
          id: other_delegate.id,
          name: other_delegate.name.presence || "Unknown",
          company: other_delegate.company&.name || "N/A"
        }
      end

      # -------------------------
      # fallback
      # -------------------------
      def unknown_delegate
        {
          id: nil,
          name: "Unknown",
          company: "N/A"
        }
      end
    end
  end
end
