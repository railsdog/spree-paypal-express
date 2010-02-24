class CreatePaypalTxns < ActiveRecord::Migration
  def self.up
      create_table :paypal_txns do |t|
      t.references :paypal_payment
      t.decimal :gross_amount, :precision => 8, :scale => 2
      t.string :payment_status
      t.text :message
      t.string :pending_reason
      t.string :transaction_type
      t.string :payment_type
      t.string :ack
      t.string :token
      t.string :avs_code
      t.string :cvv_code
      t.timestamps
    end
  end

  def self.down
    drop_table :paypal_txns
  end
end
