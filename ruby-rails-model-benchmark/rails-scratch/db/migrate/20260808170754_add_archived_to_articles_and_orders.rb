class AddArchivedToArticlesAndOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :archived, :boolean, default: false, null: false
    add_column :orders, :archived, :boolean, default: false, null: false
  end
end
