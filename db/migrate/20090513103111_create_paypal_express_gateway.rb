class CreatePaypalExpressGateway < ActiveRecord::Migration
  def self.up
    login     = GatewayOption.create(:name => "login", :description => "Your login email.")
    password  = GatewayOption.create(:name => "password", :description => "Your Paypal API Credentials Password.")
    signature = GatewayOption.create(:name => "signature", :textarea => true, :description => "Your Paypal API Credentials signature string.")

    gateway = Gateway.create(:name => "Paypal Express UK",
                             :clazz => "ActiveMerchant::Billing::PaypalExpressUkGateway",
                             :description => "Active Merchant's Paypal Express (UK) Gateway.",
                             :gateway_options => [login, password, signature])
  end

  def self.down
  end
end
