# Put your extension routes here.

map.resources :orders, :member => {:paypal_checkout => :any, :paypal_finish => :any} 

