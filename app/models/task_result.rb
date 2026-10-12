# frozen_string_literal: true

class TaskResult < ApplicationRecord
  belongs_to :eval_run

  validates :task_name, presence: true

  # TODO(you): helpers like #passed? if you store pass as boolean/nil
end
