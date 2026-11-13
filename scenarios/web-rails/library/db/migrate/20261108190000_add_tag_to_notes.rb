# frozen_string_literal: true

class AddTagToNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :notes, :tag, :string, null: false, default: ""
  end
end
