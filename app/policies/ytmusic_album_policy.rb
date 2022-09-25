# frozen_string_literal: true

class YtmusicAlbumPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
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
