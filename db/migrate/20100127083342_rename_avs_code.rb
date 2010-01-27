class RenameAvsCode < ActiveRecord::Migration
  def self.up
    rename_column :paypal_txns, :avs_code, :avs_response
    rename_column :paypal_txns, :cvv_code, :cvv_response
  end

  def self.down
    rename_column :paypal_txns, :cvv_response, :cvv_code
    rename_column :paypal_txns, :avs_response, :avs_code
  end
end