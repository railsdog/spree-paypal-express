# Put your extension routes here.

map.resources :orders do |order|
  order.resource :checkout, :member => {:paypal_checkout => :any, :paypal_payment => :any, :paypal_confirm => :any, :paypal_finish => :any}
end

map.paypal_notify "/paypal_notify", :controller => :paypal_express_callbacks, :action => :notify, :method => [:post, :get]

map.namespace :admin do |admin|
  admin.resources :orders do |order|
    order.resources :paypal_payments, :member => {:capture => :get, :refund => :any}, :has_many => [:txns]
  end
end

