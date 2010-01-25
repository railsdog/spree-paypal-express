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
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal_express_uk.rb")


    # inject paypal code into orders controller
    CheckoutsController.class_eval do
      include Spree::PaypalExpress
    end

    # probably not needed once the payments mech is generalised
    Order.class_eval do
      has_many :paypal_payments
    end
  end
end
