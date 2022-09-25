# frozen_string_literal: true

class LineMusicAlbumPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def attach_line_music_tracks?
    false
  end

  def detach_line_music_tracks?
    false
  end

  def edit_line_music_tracks?
    false
  end

  def create_line_music_tracks?
    false
  end

  def destroy_line_music_tracks?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
