# frozen_string_literal: true

# Optional DB mirror of a harness run (results/ on disk remain source of truth for Alpha MVP).
class EvalRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  has_many :task_results, dependent: :destroy

  validates :run_id, presence: true, uniqueness: true
  validates :scenario_id, :model_id, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }
end
