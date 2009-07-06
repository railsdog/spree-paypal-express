require File.dirname(__FILE__) + '/paypal_express'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalExpressUkGateway < PaypalExpressGateway
      self.default_currency = 'GBP'
      
      self.supported_countries = ['GB']
      self.homepage_url = 'https://www.paypal.com/uk/cgi-bin/webscr?cmd=_additional-payment-overview-outside'
      self.display_name = 'PayPal Express Checkout (UK)'
    end
  end
end

