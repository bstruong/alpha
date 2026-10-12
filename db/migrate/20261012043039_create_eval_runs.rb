class CreateEvalRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :eval_runs do |t|
      t.string :run_id
      t.string :scenario_id
      t.string :model_id
      t.string :prompt_preset
      t.string :engine_preset
      t.string :status
      t.decimal :pass_at_1
      t.string :summary_path
      t.string :report_path
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :eval_runs, :run_id, unique: true
  end
end
