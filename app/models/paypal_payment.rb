class PaypalPayment < Payment
  has_many :creditcard_txns, :foreign_key => 'creditcard_payment_id'  # reused and faked
  belongs_to :creditcard      # allow for saving of fake details
  # accepts_nested_attributes_for :creditcard

  alias :txns :creditcard_txns                                        # should PUSH to parent/interface

  def find_authorization
    #find the transaction associated with the original authorization/capture
    txns.find(:first,
              :conditions => ["txn_type = ? AND response_code IS NOT NULL", CreditcardTxn::TxnType::AUTHORIZE],
              :order => 'created_at DESC')
  end
  
  def can_capture?    # push to parent? perhaps not
    txns.last == find_authorization
  end
end
