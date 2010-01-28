class PaypalPayment < Payment
  has_many :paypal_txns

  alias :txns :paypal_txns

  def find_authorization
    #find the transaction associated with the original authorization/capture
    txns.find(:first,
              :conditions => {:pending_reason =>  "authorization", :payment_status => "Pending"},
              :order => 'created_at DESC')
  end

  def find_capture
    #find the transaction associated with the original authorization/capture
    txns.find(:first,
              :conditions => {:payment_status => "Completed"},
              :order => 'created_at DESC')
  end

  def can_capture?
    find_capture.nil?
  end
end
