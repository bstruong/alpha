# frozen_string_literal: true

# Optional DB mirror of a harness run (results/ on disk remain source of truth for Alpha MVP).
class EvalRun < ApplicationRecord
  has_many :task_results, dependent: :destroy

  validates :run_id, presence: true, uniqueness: true
  validates :scenario_id, :model_id, :status, presence: true

  # TODO(you): define allowed statuses (e.g. pending / running / completed / failed)
  # and any scopes you find useful while exploring ActiveRecord.
end
