# frozen_string_literal: true

class AddTitleSourceOverrideToAlbums < ActiveRecord::Migration[8.1]
  def change
    add_column :albums, :title_source_override, :string
    add_index :albums, :title_source_override
  end
end
