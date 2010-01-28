class AddTransactionIdToPpxTxn < ActiveRecord::Migration
  def self.up
    add_column :paypal_txns, :transaction_id, :string
  end

  def self.down
    remove_column :paypal_txns, :transaction_id
  end
end