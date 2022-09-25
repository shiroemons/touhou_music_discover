# frozen_string_literal: true

class SpotifyAlbumPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def act_on?
    true
  end

  def attach_spotify_tracks?
    false
  end

  def detach_spotify_tracks?
    false
  end

  def edit_spotify_tracks?
    false
  end

  def create_spotify_tracks?
    false
  end

  def destroy_spotify_tracks?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
