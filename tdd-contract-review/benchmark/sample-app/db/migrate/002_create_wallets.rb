# frozen_string_literal: true

class CreateWallets < ActiveRecord::Migration[7.1]
  def change
    create_table :wallets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :currency, null: false
      t.string :name, null: false
      t.decimal :balance, precision: 20, scale: 8, null: false, default: 0
      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    add_index :wallets, %i[user_id currency], unique: true
  end
end
