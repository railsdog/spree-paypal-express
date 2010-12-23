# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class PaypalExpressExtension < Spree::Extension
  version "1.0"
  description "Describe your extension here"
  url "http://yourwebsite.com/paypal_express"

  def activate
    BillingIntegration::PaypalExpress.register
    BillingIntegration::PaypalExpressUk.register

    # Load up over-rides for ActiveMerchant files
    # these will be submitted to ActiveMerchant some time...
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal", "paypal_common_api.rb")
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal_express_uk.rb")

    # inject paypal code into orders controller
    CheckoutsController.class_eval do
      include Spree::PaypalExpress
    end

    Checkout.class_eval do
      private
        def complete_order
          order.complete!

          # do not transition echeck order to paid regardless of auto-capture
          # echecks are finalized via IPN callback only
          if Spree::Config[:auto_capture] && !order.checkout.payments.any? {|p| payment.source.is_a?(PaypalAccount) && p.source.echeck?(p) }
            order.pay!
          end
        end
    end

  end
end
