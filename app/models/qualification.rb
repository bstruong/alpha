# frozen_string_literal: true

# Omega consumes rows (or JSON files) shaped like omega.qualification.v1.
class Qualification < ApplicationRecord
  validates :model_id, :prompt_preset, :scenario_id, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def current?
    expires_at.nil? || expires_at > Time.now.utc
  end

  def expired?
    !current?
  end
end
