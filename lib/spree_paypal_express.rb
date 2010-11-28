require 'spree_core'
require 'spree_paypal_express_hooks'

module SpreePaypalExpress
  class Engine < Rails::Engine

    config.autoload_paths += %W(#{config.root}/lib)

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), "../app/**/*_decorator*.rb")) do |c|
        Rails.env.production? ? require(c) : load(c)
      end
      BillingIntegration::PaypalExpress.register
      BillingIntegration::PaypalExpressUk.register

      # Load up over-rides for ActiveMerchant files
      # these will be submitted to ActiveMerchant some time...
      require File.join(File.dirname(__FILE__), "active_merchant", "billing", "gateways", "paypal", "paypal_common_api.rb")
      require File.join(File.dirname(__FILE__), "active_merchant", "billing", "gateways", "paypal_express_uk.rb")

      # inject paypal code into orders controller
      CheckoutController.class_eval do
        include Spree::PaypalExpress
      end
    end

    config.to_prepare &method(:activate).to_proc
  end
end
