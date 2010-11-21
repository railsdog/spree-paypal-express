class PaypalExpressCallbacksController < Spree::BaseController
  include ActiveMerchant::Billing::Integrations
  skip_before_filter :verify_authenticity_token

  def notify
    @notification = Paypal::Notification.new(request.raw_post)
    debugger

    # we only care about eChecks (for now?)
    if @notification.params["payment_type"] == "echeck" && @notification.acknowledge
      case @notification.params["payment_status"]
        when "Denied"
          retrieve_details
          create_txn PaypalTxn::TxnType::DENIED

        when "Completed"
          retrieve_details
          create_txn PaypalTxn::TxnType::CAPTURE
      end

    end

    render :nothing => true
  end

  private
    def retrieve_details
      @order = Order.find_by_number(@notification.params["invoice"])
      @payment = @order.checkout.payments.find(:first,
                                               :conditions => {"transactions.txn_type"     => PaypalTxn::TxnType::AUTHORIZE,
                                                               "transactions.payment_type" => @notification.params["payment_type"]},
                                               :joins => :transactions)
    end

    def create_txn(txn_type)
      if @payment.can_finalize?
        @payment.finalize!
        PaypalTxn.create(:payment => @payment,
                       :txn_type => txn_type,
                       :amount => @notification.params["payment_gross"].to_f,
                       :payment_status => @notification.params["payment_status"],
                       :transaction_id => @notification.params["txn_id"],
                       :transaction_type => @notification.params["txn_type"],
                       :payment_type => @notification.params["payment_type"])

      end

    end

end
