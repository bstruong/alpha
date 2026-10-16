# frozen_string_literal: true

class TaskResult < ApplicationRecord
  belongs_to :eval_run

  validates :task_name, presence: true

  scope :passed, -> { where(pass: true) }
  scope :failed, -> { where(pass: false) }

  def passed?
    pass == true
  end
end
