# frozen_string_literal: true

class CirclePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def attach_albums?
    false
  end

  def detach_albums?
    false
  end

  def edit_albums?
    false
  end

  def create_albums?
    false
  end

  def destroy_albums?
    false
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
