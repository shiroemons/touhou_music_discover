# frozen_string_literal: true

class OriginalPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def attach_original_songs?
    false
  end

  def detach_original_songs?
    false
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

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
