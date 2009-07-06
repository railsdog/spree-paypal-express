# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class PaypalExpressExtension < Spree::Extension
  version "1.0"
  description "Describe your extension here"
  url "http://yourwebsite.com/paypal_express"

  # Please use paypal_express/config/routes.rb instead for extension routes.

  # def self.require_gems(config)
  #   config.gem "gemname-goes-here", :version => '1.2.3'
  # end
  
  def activate
    # admin.tabs.add "Paypal Express", "/admin/paypal_express", :after => "Layouts", :visibility => [:all]
   
    # Load up over-rides for ActiveMerchant files
    # these will be submitted to ActiveMerchant some time...
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal", "paypal_common_api.rb")
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal_express_uk.rb")
    require File.join(PaypalExpressExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal_express_uk.rb")

   
    # inject paypal code into orders controller 
    OrdersController.class_eval do
      ssl_required :paypal_checkout, :paypal_finish
      include Spree::PaypalExpress
    end

    # probably not needed once the payments mech is generalised
    Order.class_eval do
      has_many :paypal_payments
    end
  end
end
