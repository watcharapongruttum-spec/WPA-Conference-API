module Api
  module V1
    class ProfileController < BaseController

      def show
        delegate = find_delegate
        return render_not_found unless delegate

        render json: build_profile_json(delegate)
      end

      def update
        if current_delegate.update(profile_params)
          render json: build_profile_json(current_delegate)
        else
          render json: {
            success: false,
            errors: current_delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      # ----------------------------
      # Safe delegate lookup
      # ----------------------------
      def find_delegate
        if params[:id].present?
          Delegate.includes(:company, :team).find_by(id: params[:id])
        else
          current_delegate
        end
      end

      def render_not_found
        render json: { error: "Not found" }, status: :not_found
      end

      # ----------------------------
      # Strong params
      # ----------------------------
      def profile_params
        params.permit(
          :name,
          :title,
          :phone,
          :spouse_attending,
          :spouse_name,
          :need_room,
          :booking_no
        )
      end

      # ----------------------------
      # JSON Builder (Safe + Clean)
      # ----------------------------
      def build_profile_json(delegate)
        company = delegate.company
        team = delegate.team

        {
          id: delegate.id,
          name: delegate.name,
          title: delegate.title,
          email: delegate.email,
          phone: delegate.phone,
          avatar_url: avatar_url_for(delegate.name),

          company: company && {
            id: company.id,
            name: company.name,
            country: company.country
          },

          team: team && {
            id: team.id,
            name: team.name,
            country_code: team.country_code
          },

          first_conference: delegate.first_conference,
          spouse_attending: delegate.spouse_attending,
          spouse_name: delegate.spouse_name,
          need_room: delegate.need_room,
          booking_no: delegate.booking_no
        }
      end

      def avatar_url_for(name)
        return nil if name.blank?

        "https://ui-avatars.com/api/?name=#{CGI.escape(name)}&background=0D8ABC&color=fff"
      end

    end
  end
end
