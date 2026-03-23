# app/controllers/api/v1/admin/messages_controller.rb
module Api
  module V1
    module Admin
      class MessagesController < Api::V1::Admin::BaseController

        # ─── รายการห้อง direct chat ทั้งหมด ───────────────────
        def rooms
        page     = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 20).to_i, 100].min

        # ─── base query ───────────────────────────────────────
        pairs_query = ChatMessage
                        .where(chat_room_id: nil)
                        .where.not(recipient_id: nil)
                        .where(deleted_at: nil)
                        .select(
                            Arel.sql(
                            "LEAST(sender_id, recipient_id)    AS user_a_id,
                            GREATEST(sender_id, recipient_id) AS user_b_id,
                            MAX(created_at)                   AS last_message_at,
                            COUNT(*)                          AS message_count"
                            )
                        )
                        .group(
                            Arel.sql("LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id)")
                        )
                        .order(Arel.sql("MAX(created_at) DESC"))

        # ─── count ด้วย subquery แทน ──────────────────────────
        total       = ChatMessage
                        .from(pairs_query, :pairs)
                        .count
        total_pages = (total.to_f / per_page).ceil
        pairs       = pairs_query.offset((page - 1) * per_page).limit(per_page)

        delegate_ids = pairs.flat_map { |p| [p.user_a_id, p.user_b_id] }.uniq
        delegates    = Delegate.includes(:company).where(id: delegate_ids).index_by(&:id)

        last_messages = ChatMessage
                            .where(chat_room_id: nil)
                            .where.not(recipient_id: nil)
                            .select(
                            Arel.sql(
                                "DISTINCT ON (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id))
                                id, content, message_type, sender_id, recipient_id, created_at, read_at"
                            )
                            )
                            .order(
                            Arel.sql(
                                "LEAST(sender_id, recipient_id),
                                GREATEST(sender_id, recipient_id),
                                created_at DESC"
                            )
                            )
                            .index_by { |m| [m.sender_id, m.recipient_id].minmax }

        rooms = pairs.map do |pair|
            a_id       = pair.user_a_id
            b_id       = pair.user_b_id
            delegate_a = delegates[a_id]
            delegate_b = delegates[b_id]
            last_msg   = last_messages[[a_id, b_id]]

            unread_count = ChatMessage
                            .where(chat_room_id: nil, read_at: nil, deleted_at: nil)
                            .where(
                            "(sender_id = :a AND recipient_id = :b) OR
                                (sender_id = :b AND recipient_id = :a)",
                            a: a_id, b: b_id
                            ).count

            {
            delegate_a: delegate_a && {
                id:         delegate_a.id,
                name:       delegate_a.name,
                avatar_url: delegate_a.avatar_url,
                company:    delegate_a.company&.name
            },
            delegate_b: delegate_b && {
                id:         delegate_b.id,
                name:       delegate_b.name,
                avatar_url: delegate_b.avatar_url,
                company:    delegate_b.company&.name
            },
            message_count:     pair.message_count,
            unread_count:      unread_count,
            last_message:      last_msg&.content.to_s.truncate(50),
            last_message_type: last_msg&.message_type,
            last_message_at:   last_msg&.created_at&.iso8601
            }
        end

        render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: total_pages,
            rooms:       rooms
        }
        end








        # ─── ดูข้อความระหว่าง 2 คน ────────────────────────────
        def direct
          delegate_a = params[:delegate_a_id]
          delegate_b = params[:delegate_b_id]
          page       = (params[:page] || 1).to_i
          per        = [(params[:per] || 50).to_i, 100].min

          unless delegate_a.present? && delegate_b.present?
            return render json: { error: "delegate_a_id and delegate_b_id are required" },
                          status: :unprocessable_entity
          end

          unless Delegate.exists?(delegate_a) && Delegate.exists?(delegate_b)
            return render json: { error: "Delegate not found" }, status: :not_found
          end

          scope = ChatMessage
                    .where(chat_room_id: nil)
                    .where(
                      "(sender_id = :a AND recipient_id = :b) OR
                       (sender_id = :b AND recipient_id = :a)",
                      a: delegate_a, b: delegate_b
                    )
                    .includes(:sender, :recipient)
                    .order(created_at: :desc)

          total          = scope.count
          msgs           = scope.offset((page - 1) * per).limit(per)
          delegate_a_obj = Delegate.find(delegate_a)
          delegate_b_obj = Delegate.find(delegate_b)

          render json: {
            total:       total,
            page:        page,
            per:         per,
            total_pages: (total.to_f / per).ceil,
            delegate_a: {
              id:         delegate_a_obj.id,
              name:       delegate_a_obj.name,
              avatar_url: delegate_a_obj.avatar_url
            },
            delegate_b: {
              id:         delegate_b_obj.id,
              name:       delegate_b_obj.name,
              avatar_url: delegate_b_obj.avatar_url
            },
            messages: msgs.map { |m|
              {
                id:           m.id,
                content:      m.content,
                message_type: m.message_type,
                image_url:    m.image_url,
                created_at:   m.created_at&.iso8601,
                is_deleted:   m.deleted_at.present?,
                read_at:      m.read_at&.iso8601,
                sender: {
                  id:         m.sender.id,
                  name:       m.sender.name,
                  avatar_url: m.sender.avatar_url
                }
              }
            }
          }
        end

      end
    end
  end
end