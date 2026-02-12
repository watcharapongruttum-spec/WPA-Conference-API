module Api
  module V1
    class ProfileController < BaseController

      def show
        delegate = current_delegate
        render json: profile_json(delegate)
      end

      def update
        delegate = current_delegate

        if delegate.update(profile_params)
          render json: profile_json(delegate)
        else
          render json: {
            success: false,
            errors: delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

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

      def profile_json(delegate)
        {
          id: delegate.id,
          name: delegate.name,
          title: delegate.title,
          email: delegate.email,
          phone: delegate.phone,
          company: {
            id: delegate.company.id,
            name: delegate.company.name,
            country: delegate.company.country,
            logo_url: nil
          },
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff",
          team: delegate.team ? {
            id: delegate.team.id,
            name: delegate.team.name,
            country_code: delegate.team.country_code
          } : nil,
          first_conference: delegate.first_conference,
          spouse_attending: delegate.spouse_attending,
          spouse_name: delegate.spouse_name,
          need_room: delegate.need_room,
          booking_no: delegate.booking_no
        }
      end

    end
  end
end
