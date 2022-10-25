# frozen_string_literal: true

class TrackPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def act_on?
    true
  end

  def attach_original_songs?
    true
  end

  def detach_original_songs?
    true
  end

  def edit_original_songs?
    false
  end

  def create_original_songs?
    false
  end

  def destroy_original_songs?
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

  def upload_attachments?
    true
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
