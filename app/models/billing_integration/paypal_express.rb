class BillingIntegration::PaypalExpress < BillingIntegration
  preference :login, :string
  preference :password, :password
  preference :signature, :string

  def provider_class
    ActiveMerchant::Billing::PaypalExpressGateway
  end

end
