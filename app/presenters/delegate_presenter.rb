# app/presenters/delegate_presenter.rb
#
# Central helper สำหรับ serialize delegate เป็น hash
# ใช้แทนการเขียน { id:, name:, avatar_url: } ซ้ำๆ ทั่ว codebase
#
module DelegatePresenter
  # ── minimal: id, name, avatar_url ──────────────────────────────
  # ใช้ใน: notification payloads, reader lists, typing indicators
  def self.minimal(delegate)
    return nil unless delegate

    {
      id:         delegate.id,
      name:       delegate.name,
      avatar_url: delegate.avatar_url
    }
  end

  # ── basic: + title, company_name ───────────────────────────────
  # ใช้ใน: connection requests, chat message sender/recipient
  def self.basic(delegate)
    return nil unless delegate

    {
      id:           delegate.id,
      name:         delegate.name,
      title:        delegate.title,
      company_name: delegate.company&.name,
      avatar_url:   delegate.avatar_url
    }
  end

  # ── full: + company hash, team hash ────────────────────────────
  # ใช้ใน: directory, profile
  def self.full(delegate)
    return nil unless delegate

    {
      id:         delegate.id,
      name:       delegate.name,
      title:      delegate.title,
      avatar_url: delegate.avatar_url,
      company: delegate.company && {
        id:      delegate.company.id,
        name:    delegate.company.name,
        country: delegate.company.country
      },
      team: delegate.team && {
        id:           delegate.team.id,
        name:         delegate.team.name,
        country_code: delegate.team.country_code
      }
    }
  end
end