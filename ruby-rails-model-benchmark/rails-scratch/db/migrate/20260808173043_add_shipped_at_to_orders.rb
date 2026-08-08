class AddShippedAtToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :shipped_at, :datetime
  end
end
