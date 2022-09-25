# frozen_string_literal: true

class AlbumPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def attach_circles?
    true
  end

  def detach_circles?
    true
  end

  def edit_circles?
    false
  end

  def create_circles?
    false
  end

  def destroy_circles?
    false
  end

  def attach_tracks?
    false
  end

  def detach_tracks?
    false
  end

  def edit_tracks?
    false
  end

  def create_tracks?
    false
  end

  def destroy_tracks?
    false
  end

  def attach_apple_music_album?
    false
  end

  def detach_apple_music_album?
    false
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

  def attach_line_music_album?
    false
  end

  def detach_line_music_album?
    false
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

  def attach_spotify_album?
    false
  end

  def detach_spotify_album?
    false
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

  def attach_ytmusic_album?
    false
  end

  def detach_ytmusic_album?
    false
  end

  def attach_ytmusic_tracks?
    false
  end

  def detach_ytmusic_tracks?
    false
  end

  def edit_ytmusic_tracks?
    false
  end

  def create_ytmusic_tracks?
    false
  end

  def destroy_ytmusic_tracks?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
