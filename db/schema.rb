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

ActiveRecord::Schema[8.1].define(version: 2026_10_12_043041) do
  create_table "eval_runs", force: :cascade do |t|
    t.string "run_id"
    t.string "scenario_id"
    t.string "model_id"
    t.string "prompt_preset"
    t.string "engine_preset"
    t.string "status"
    t.decimal "pass_at_1"
    t.string "summary_path"
    t.string "report_path"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_eval_runs_on_run_id", unique: true
  end

  create_table "qualifications", force: :cascade do |t|
    t.string "model_id"
    t.string "prompt_preset"
    t.string "engine_preset"
    t.string "role"
    t.string "alpha_run_id"
    t.string "scenario_id"
    t.decimal "pass_at_1"
    t.string "report_uri"
    t.datetime "qualified_at"
    t.datetime "expires_at"
    t.string "node_class"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "task_results", force: :cascade do |t|
    t.integer "eval_run_id", null: false
    t.string "task_name"
    t.boolean "pass"
    t.integer "tool_calls"
    t.integer "prompt_tokens"
    t.integer "completion_tokens"
    t.integer "wall_ms"
    t.json "grader_detail"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["eval_run_id"], name: "index_task_results_on_eval_run_id"
  end

  add_foreign_key "task_results", "eval_runs"
end
