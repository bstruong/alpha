Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :accounts, only: [ :update ]
  resources :books, only: [ :destroy ]
  resources :notes, only: [ :index, :create ]

  post "tools/summarize", to: "tools#summarize", as: :tools_summarize
  post "tools/parse_config", to: "tools#parse_config", as: :tools_parse_config

  root "notes#index"
end
