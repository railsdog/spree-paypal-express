class PaypalAccount < ActiveRecord::Base
  has_many :payments, :as => :source

  def finalize!(payment)
    authorization = find_authorization(payment)

    ppx_response = payment.payment_method.provider.capture((100 * payment.amount).to_i, authorization.transaction_id)
    if ppx_response.success?
      transaction = PaypalTxn.new(:payment => payment,
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
    else
      gateway_error(ppx_response)
    end

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

  def can_capture?(payment)
    find_capture.nil?
  end

  def gateway_error(text)
    msg = "#{I18n.t('gateway_error')} ... #{text}"
    logger.error(msg)
    raise Spree::GatewayError.new(msg)
  end
end
