class PaypalExpressCallbacksController < Spree::BaseController
  include ActiveMerchant::Billing::Integrations
  skip_before_filter :verify_authenticity_token

  def notify
    retrieve_details #need to retreive details first to ensure ActiveMerchant gets configured correctly.

    @notification = Paypal::Notification.new(request.raw_post)

    # we only care about eChecks (for now?)
    if @notification.params["payment_type"] == "echeck" && @notification.acknowledge && @payment
      case @notification.params["payment_status"]
        when "Denied"
          create_txn PaypalTxn::TxnType::DENIED

        when "Completed"
          create_txn PaypalTxn::TxnType::CAPTURE
      end

    end

    render :nothing => true
  end

  private
    def retrieve_details
      @order = Order.find_by_number(params["invoice"])

      if @order
        @payment = @order.checkout.payments.find(:first,
                                               :conditions => {"transactions.txn_type"     => PaypalTxn::TxnType::AUTHORIZE,
                                                               "transactions.payment_type" => params["payment_type"]},
                                               :joins => :transactions)

        @payment.try(:payment_method).try(:provider) #configures ActiveMerchant
      end
    end

    def create_txn(txn_type)
      if txn_type == PaypalTxn::TxnType::CAPTURE
        @payment.finalize! if @payment.can_finalize?
      elsif txn_type == PaypalTxn::TxnType::DENIED
        #maybe we should do something?
      end

      PaypalTxn.create(:payment => @payment,
                       :txn_type => txn_type,
                       :amount => @notification.params["payment_gross"].to_f,
                       :payment_status => @notification.params["payment_status"],
                       :transaction_id => @notification.params["txn_id"],
                       :transaction_type => @notification.params["txn_type"],
                       :payment_type => @notification.params["payment_type"])


    end

end
