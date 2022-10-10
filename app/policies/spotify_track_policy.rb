# frozen_string_literal: true

class SpotifyTrackPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def act_on?
    true
  end

  def attach_spotify_track_audio_feature?
    false
  end

  def detach_spotify_track_audio_feature?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
