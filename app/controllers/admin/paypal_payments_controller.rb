class Admin::PaypalPaymentsController < Admin::BaseController
  resource_controller
  belongs_to :order
  ssl_required

  # to allow capture (NB also included in checkout controller...)
  include Spree::PaypalExpress

  def capture
    load_object
    if !@order.paypal_payments.empty? && (payment = @order.paypal_payments.last).can_capture?

      paypal_capture(payment.find_authorization)

      flash[:notice] = t("paypal_capture_complete")
    else
      flash[:error] = t("unable_to_capture_paypal")
    end
    redirect_to edit_admin_order_payment_url(@order, @paypal_payment)
  end


  def refund
    load_object
    if params.has_key? :amount

      if !@order.paypal_payments.empty?
        payment = @order.paypal_payments.first

        paypal_refund(payment.find_capture, params[:amount].to_f)

        flash[:notice] = t("paypal_refund_complete")
      else
        flash[:error] = t("unable_to_refund_paypal")
      end
      redirect_to edit_admin_order_payment_url(@order, @paypal_payment)


    end
  end


end
