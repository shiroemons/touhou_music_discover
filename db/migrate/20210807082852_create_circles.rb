# frozen_string_literal: true

class CreateCircles < ActiveRecord::Migration[6.1]
  def change
    create_table :circles, id: :uuid do |t|
      t.string :name, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
