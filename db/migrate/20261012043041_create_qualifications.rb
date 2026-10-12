class CreateQualifications < ActiveRecord::Migration[8.1]
  def change
    create_table :qualifications do |t|
      t.string :model_id
      t.string :prompt_preset
      t.string :engine_preset
      t.string :role
      t.string :alpha_run_id
      t.string :scenario_id
      t.decimal :pass_at_1
      t.string :report_uri
      t.datetime :qualified_at
      t.datetime :expires_at
      t.string :node_class

      t.timestamps
    end
  end
end
