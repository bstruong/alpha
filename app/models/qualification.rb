# frozen_string_literal: true

# Omega consumes rows (or JSON files) shaped like omega.qualification.v1.
class Qualification < ApplicationRecord
  validates :model_id, :prompt_preset, :scenario_id, presence: true

  # TODO(you): #current? / #expired? based on expires_at
  # TODO(you): uniqueness on [model_id, prompt_preset, role] if that matches your contract
end
