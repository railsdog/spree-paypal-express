class PaypalAccount < ActiveRecord::Base
  has_many :payments, :as => :source

  def actions
    %w{capture credit}
  end

  def capture(payment)
    authorization = find_authorization(payment)

    ppx_response = payment.payment_method.provider.capture((100 * payment.amount).to_i, authorization.transaction_id)
    if ppx_response.success?
      PaypalTxn.create(:payment => payment,
                      :txn_type => PaypalTxn::TxnType::CAPTURE,
                      :amount   => ppx_response.params["gross_amount"].to_f,
                      :message => ppx_response.params["message"],
                      :payment_status => ppx_response.params["payment_status"],
                      :pending_reason => ppx_response.params["pending_reason"],
                      :transaction_id => ppx_response.params["transaction_id"],
                      :transaction_type => ppx_response.params["transaction_type"],
                      :payment_type => ppx_response.params["payment_type"],
                      :response_code => ppx_response.params["ack"],
                      :token => ppx_response.params["token"],
                      :avs_response => ppx_response.avs_result["code"],
                      :cvv_response => ppx_response.cvv_result["code"])

      payment.finalize!
    else
      gateway_error(ppx_response.message)
    end

  end

  def can_capture?(payment)
    find_capture(payment).nil?
  end

  def credit(payment, amount=nil)
    authorization = find_capture(payment)

    ppx_response = payment.payment_method.provider.credit(amount.nil? ? (100 * amount).to_i : (100 * amount).to_i, authorization.transaction_id)

    if ppx_response.success?
      payment = authorization.paypal_payment

      PaypalTxn.new(:paypal_payment => payment,
                    :txn_type => PaypalTxn::TxnType::CREDIT,
                    :gross_amount   => ppx_response.params["gross_refund_amount"].to_f,
                    :message => ppx_response.params["message"],
                    :payment_status => "Refunded",
                    :pending_reason => ppx_response.params["pending_reason"],
                    :transaction_id => ppx_response.params["refund_transaction_id"],
                    :transaction_type => ppx_response.params["transaction_type"],
                    :payment_type => ppx_response.params["payment_type"],
                    :response_code => ppx_response.params["ack"],
                    :token => ppx_response.params["token"],
                    :avs_response => ppx_response.avs_result["code"],
                    :cvv_response => ppx_response.cvv_result["code"])


    else
      gateway_error(ppx_response.message)
    end
  end

  def can_credit?(payment)
    !find_capture(payment).nil?
  end
  
  # fix for Payment#payment_profiles_supported?
  def payment_gateway
    false
  end

  private
  def find_authorization(payment)
    #find the transaction associated with the original authorization/capture
    payment.txns.find(:first,
              :conditions => {:pending_reason =>  "authorization", :payment_status => "Pending", :txn_type => PaypalTxn::TxnType::AUTHORIZE.to_s},
              :order => 'created_at DESC')
  end

  def find_capture(payment)
    #find the transaction associated with the original authorization/capture
    payment.txns.find(:first,
              :conditions => {:payment_status => "Completed", :txn_type => PaypalTxn::TxnType::CAPTURE.to_s},
              :order => 'created_at DESC')
  end



  def gateway_error(text)
    msg = "#{I18n.t('gateway_error')} ... #{text}"
    logger.error(msg)
    raise Spree::GatewayError.new(msg)
  end
end
