Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Optional JSON browser for past runs — stubs only. Prefer bin/alpha for execution.
  resources :eval_runs, only: %i[index show create], param: :run_id
end
