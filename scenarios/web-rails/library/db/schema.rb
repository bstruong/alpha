# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_08_190000) do
  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "original_email"
    t.string "role", default: "member", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "books", force: :cascade do |t|
    t.integer "account_id"
    t.string "title", null: false
    t.string "author", null: false
    t.boolean "shared", default: false, null: false
    t.integer "page_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_books_on_account_id"
  end

  create_table "drafts", force: :cascade do |t|
    t.integer "book_id", null: false
    t.text "body", null: false
    t.boolean "superseded", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_drafts_on_book_id"
  end

  create_table "grants", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "book_id", null: false
    t.string "level", default: "reader", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_grants_on_account_id"
    t.index ["book_id"], name: "index_grants_on_book_id"
  end

  create_table "notes", force: :cascade do |t|
    t.string "title", null: false
    t.string "tag", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "receipts", force: :cascade do |t|
    t.integer "account_id", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "idempotency_key", null: false
    t.datetime "claimed_at"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_receipts_on_account_id"
    t.index ["idempotency_key"], name: "index_receipts_on_idempotency_key", unique: true
  end

  create_table "search_entries", force: :cascade do |t|
    t.integer "book_id", null: false
    t.string "term", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_search_entries_on_book_id"
  end

  create_table "sign_ins", force: :cascade do |t|
    t.string "email", null: false
    t.datetime "signed_in_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "books", "accounts"
  add_foreign_key "drafts", "books"
  add_foreign_key "grants", "accounts"
  add_foreign_key "grants", "books"
  add_foreign_key "receipts", "accounts"
  add_foreign_key "search_entries", "books"
end
