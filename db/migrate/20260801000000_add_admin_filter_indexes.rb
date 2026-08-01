# frozen_string_literal: true

class AddAdminFilterIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :originals, :original_type, if_not_exists: true, algorithm: :concurrently
    add_index :circles, :created_at, if_not_exists: true, algorithm: :concurrently
  end
end
