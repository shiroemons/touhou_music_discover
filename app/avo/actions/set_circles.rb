# frozen_string_literal: true

class SetCircles < Avo::BaseAction
  self.name = 'サークルを設定'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    CircleAssignmentService.new.assign_missing
    succeed 'Done!'
    reload
  end
end
