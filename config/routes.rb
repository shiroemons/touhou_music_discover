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
    get 'playlists/progress_stream', to: 'playlists#progress_stream'
    get 'playlists/original_songs', to: 'playlists#original_songs'
    delete 'playlists/cache', to: 'playlists#clear_cache', as: :clear_playlists_cache
    post 'playlists/:id/sync', to: 'playlists#sync_single', as: :playlist_sync
    post 'playlists/refresh_counts', to: 'playlists#refresh_counts'
    get 'playlists/refresh_counts_stream', to: 'playlists#refresh_counts_stream'
  end
end
