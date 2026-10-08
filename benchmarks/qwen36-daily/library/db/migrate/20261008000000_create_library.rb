class CreateLibrary < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :original_email
      t.string :role, null: false, default: "member"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :accounts, :email, unique: true

    create_table :books do |t|
      t.references :account, foreign_key: true
      t.string :title, null: false
      t.string :author, null: false
      t.boolean :shared, null: false, default: false
      t.integer :page_count, null: false, default: 0
      t.timestamps
    end

    create_table :drafts do |t|
      t.references :book, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :superseded, null: false, default: false
      t.timestamps
    end

    create_table :search_entries do |t|
      t.references :book, null: false, foreign_key: true
      t.string :term, null: false
      t.timestamps
    end

    create_table :grants do |t|
      t.references :account, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.string :level, null: false, default: "reader"
      t.timestamps
    end

    create_table :receipts do |t|
      t.references :account, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :idempotency_key, null: false
      t.datetime :claimed_at
      t.datetime :sent_at
      t.timestamps
    end
    add_index :receipts, :idempotency_key, unique: true

    create_table :sign_ins do |t|
      t.string :email, null: false
      t.datetime :signed_in_at, null: false
      t.timestamps
    end
  end
end
