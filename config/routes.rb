Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  namespace :treasury do
    resources :accounts, only: [:index, :show]
    resources :statement_imports, only: [:create]
  end

  namespace :api do
    namespace :v1 do
      resources :accounts, only: [] do
        resource :reconciled_balance, only: [:show]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
  root "treasury/accounts#index"
end
