# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.decimal :amount, precision: 20, scale: 8, null: false
      t.string :currency, null: false
      t.string :status, null: false, default: 'pending'
      t.string :description
      t.string :category, null: false, default: 'transfer'

      t.timestamps
    end

    add_index :transactions, %i[user_id created_at]
    add_index :transactions, :status
  end
end
