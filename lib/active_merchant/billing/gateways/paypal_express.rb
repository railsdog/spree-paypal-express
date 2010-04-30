#require File.dirname(__FILE__) + '/paypal/paypal_common_api'
#require File.dirname(__FILE__) + '/paypal/paypal_express_response'
#require File.dirname(__FILE__) + '/paypal_express_common'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalExpressGateway < Gateway
      include PaypalCommonAPI
      include PaypalExpressCommon

      self.test_redirect_url = 'https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token='
      self.supported_countries = ['US']
      self.homepage_url = 'https://www.paypal.com/cgi-bin/webscr?cmd=xpt/merchant/ExpressCheckoutIntro-outside'
      self.display_name = 'PayPal Express Checkout'

      def setup_authorization(money, options = {})
        requires!(options, :return_url, :cancel_return_url)
        commit 'SetExpressCheckout', build_setup_request('Authorization', money, options)
      end

      def setup_purchase(money, options = {})
        requires!(options, :return_url, :cancel_return_url)

        commit 'SetExpressCheckout', build_setup_request('Sale', money, options)
      end

      def details_for(token)
        commit 'GetExpressCheckoutDetails', build_get_details_request(token)
      end

      def authorize(money, options = {})
        requires!(options, :token, :payer_id)

        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Authorization', money, options)
      end

      def purchase(money, options = {})
        requires!(options, :token, :payer_id)

        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Sale', money, options)
      end

      private
      def build_get_details_request(token)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetExpressCheckoutDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetExpressCheckoutDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'Token', token
          end
        end

        xml.target!
      end

      def build_sale_or_authorization_request(action, money, options)
        currency_code = options[:currency] || currency(money)

        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'DoExpressCheckoutPaymentReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'DoExpressCheckoutPaymentRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:DoExpressCheckoutPaymentRequestDetails' do
              xml.tag! 'n2:PaymentAction', action
              xml.tag! 'n2:Token', options[:token]
              xml.tag! 'n2:PayerID', options[:payer_id]
              add_payment_details(xml, money, options)
            end
          end
        end

        xml.target!
      end

      def build_setup_request(action, money, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'SetExpressCheckoutReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'SetExpressCheckoutRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:SetExpressCheckoutRequestDetails' do
              if options[:max_amount]
                xml.tag! 'n2:MaxAmount', amount(options[:max_amount]), 'currencyID' => options[:currency] || currency(options[:max_amount])
              end
              xml.tag! 'n2:ReturnURL', options[:return_url]
              xml.tag! 'n2:CancelURL', options[:cancel_return_url]
              # xml.tag! 'n2:CallbackURL', options[:callback_url] unless options[:callback_url].blank?
              # xml.tag! 'n2:CallbackTimeout', options[:callback_timeout] unless options[:callback_timeout].blank?
              xml.tag! 'n2:ReqConfirmShipping', options[:req_confirm_shipping] ? '1' : '0'
              xml.tag! 'n2:NoShipping', options[:no_shipping] ? '1' : '0'
              ## add flat rates for shipping
              # add_shipping_options(xml, options[:shipping_options], options) if options[:shipping_options]
              xml.tag! 'n2:AllowNote', options[:allow_note] ? '1' : '0'
              xml.tag! 'n2:AddressOverride', options[:address_override] ? '1' : '0' # force yours
              xml.tag! 'n2:LocaleCode', options[:locale] unless options[:locale].blank?

              # Customization of the payment page
              xml.tag! 'n2:PageStyle', options[:page_style] unless options[:page_style].blank?
              xml.tag! 'n2:cpp-header-image', options[:header_image] unless options[:header_image].blank?
              xml.tag! 'n2:cpp-header-border-color', options[:header_border_color] unless options[:header_border_color].blank?
              xml.tag! 'n2:cpp-header-back-color', options[:header_background_color] unless options[:header_background_color].blank?
              xml.tag! 'n2:cpp-payflow-color', options[:background_color] unless options[:background_color].blank?

              xml.tag! 'n2:PaymentAction', action
              xml.tag! 'n2:BuyerEmail', options[:email] unless options[:email].blank?
              xml.tag! 'n2:SolutionType', options[:solution_type] unless options[:solution_type].blank?
              xml.tag! 'n2:LandingPage', options[:landing_page] unless options[:landing_page].blank?
              xml.tag! 'n2:ChannelType', options[:channel_type] unless options[:channel_type].blank?

              # only needed for certain methods in Germany
              xml.tag! 'n2:giropaySuccessURL', options[:giropay_url] unless options[:giropay_url].blank?
              xml.tag! 'n2:giropayCancelURL', options[:giropay_cancel_url] unless options[:giropay_cancel_url].blank?
              xml.tag! 'n2:BanktxnPendingURL', options[:banktxn_url] unless options[:banktxn_url].blank?

              # for order values etc, and item info
              add_payment_details(xml, money, options)
            end
          end
        end

        xml.target!
      end

      def build_response(success, message, response, options = {})
        PaypalExpressResponse.new(success, message, response, options)
      end
    end
  end
end
