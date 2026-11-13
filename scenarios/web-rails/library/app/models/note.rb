# frozen_string_literal: true

class Note < ApplicationRecord
  validates :title, presence: true

  scope :search, ->(q) {
    q = q.to_s.strip
    q.empty? ? all : where("title LIKE ?", "%#{sanitize_sql_like(q)}%")
  }

  scope :with_tag, ->(tag) {
    tag = tag.to_s.strip
    tag.empty? ? all : where(tag: tag)
  }
end
