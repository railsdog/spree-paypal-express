class PaypalTxn < ActiveRecord::Base
  belongs_to :paypal_payment
end
