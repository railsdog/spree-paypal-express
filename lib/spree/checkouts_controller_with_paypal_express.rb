module Spree::CheckoutsControllerWithPaypalExpress
  def self.included(target)
    target.before_filter :redirect_to_paypal_express_form, :only => [:update]
  end
  
  private
end