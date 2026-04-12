# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :encrypted_password, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
