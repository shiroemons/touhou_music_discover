# frozen_string_literal: true

Rails.application.routes.draw do
  root to: 'root#index'

  get '/auth/:provider/callback', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
end
