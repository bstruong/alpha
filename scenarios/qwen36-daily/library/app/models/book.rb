class Book < ApplicationRecord
  belongs_to :account, optional: true
  has_many :drafts, dependent: :destroy
  has_many :search_entries, dependent: :destroy
  has_many :grants, dependent: :destroy

  def leaf_count
    drafts.count
  end
end
