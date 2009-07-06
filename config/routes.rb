# Put your extension routes here.

map.resources :orders, :member => {:paypal_checkout => :any, :paypal_finish => :any}

map.namespace :admin do |admin|
  admin.resources :orders do |order|
    order.resources :paypal_payments, :member => {:capture => :get}, :has_many => [:paypal_payments]
  end
end

