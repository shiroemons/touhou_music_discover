# frozen_string_literal: true

class AppleMusicAlbumPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def act_on?
    true
  end

  def attach_apple_music_tracks?
    false
  end

  def detach_apple_music_tracks?
    false
  end

  def edit_apple_music_tracks?
    false
  end

  def create_apple_music_tracks?
    false
  end

  def destroy_apple_music_tracks?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
