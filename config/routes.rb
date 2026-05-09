# frozen_string_literal: true

Rails.application.routes.draw do
  get 'up' => 'rails/health#show', as: :rails_health_check

  namespace :admin do
    root to: 'dashboard#show'
    constraints resource: Admin::Resource.route_constraint do
      get ':resource', to: 'resources#index', as: :resources
      post ':resource', to: 'resources#create'
      get ':resource/new', to: 'resources#new', as: :new_resource
      get ':resource/actions/:action_key', to: 'actions#new', as: :resource_action
      post ':resource/actions/:action_key', to: 'actions#create'
      get ':resource/actions/:action_key/runs/:run_id', to: 'actions#show', as: :resource_action_run
      get ':resource/actions/:action_key/runs/:run_id/progress', to: 'actions#progress', as: :resource_action_run_progress
      get ':resource/:id/actions/:action_key', to: 'actions#new', as: :member_resource_action
      post ':resource/:id/actions/:action_key', to: 'actions#create'
      get ':resource/:id/actions/:action_key/runs/:run_id', to: 'actions#show', as: :member_resource_action_run
      get ':resource/:id/actions/:action_key/runs/:run_id/progress', to: 'actions#progress', as: :member_resource_action_run_progress
      get ':resource/association_options/:attribute', to: 'association_options#index', as: :resource_association_options
      post ':resource/:id/relations/:association', to: 'relations#create', as: :resource_relation
      delete ':resource/:id/relations/:association/:related_id', to: 'relations#destroy', as: :resource_relation_record
      get ':resource/:id', to: 'resources#show', as: :resource
      get ':resource/:id/edit', to: 'resources#edit', as: :edit_resource
      patch ':resource/:id', to: 'resources#update'
      delete ':resource/:id', to: 'resources#destroy'
    end
  end

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
