class CreateTaskResults < ActiveRecord::Migration[8.1]
  def change
    create_table :task_results do |t|
      t.references :eval_run, null: false, foreign_key: true
      t.string :task_name
      t.boolean :pass
      t.integer :tool_calls
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :wall_ms
      t.json :grader_detail

      t.timestamps
    end
  end
end
