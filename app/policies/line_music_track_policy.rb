# frozen_string_literal: true

class LineMusicTrackPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def act_on?
    true
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
