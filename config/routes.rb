# frozen_string_literal: true

Rails.application.routes.draw do
  mount Avo::Engine, at: Avo.configuration.root_path
  root to: 'root#index'
  get '/albums', to: 'albums#index'

  get '/auth/:provider/callback', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'

  namespace :spotify do
    get 'playlists', to: 'playlists#index'
    match 'playlists/create', to: 'playlists#create', via: %i[get post]
    get 'playlists/progress', to: 'playlists#progress'
  end
end
