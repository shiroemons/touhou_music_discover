# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :name, null: false
      t.string :email, null: false, default: ''
      t.string :nickname, null: false, default: ''
      t.string :description, null: false, default: ''
      t.string :image_url, null: false, default: ''

      t.timestamps
    end
  end
end
