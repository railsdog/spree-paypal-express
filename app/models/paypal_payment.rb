class PaypalPayment < Payment
  has_many :paypal_txns

  alias :txns :paypal_txns

  # def find_authorization
  #   #find the transaction associated with the original authorization/capture
  #   txns.find(:first,
  #             :conditions => ["txn_type = ? AND response_code IS NOT NULL", CreditcardTxn::TxnType::AUTHORIZE],
  #             :order => 'created_at DESC')
  # end

  def can_capture?    # push to parent? perhaps not
    true
    #txns.last == find_authorization
  end
end
