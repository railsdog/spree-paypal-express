# WARNING: the details of UK tax and my site's shipping are a bit hard-coded here for now
# aim to unpick this later
module Spree::PaypalExpress
  include ERB::Util
  include Spree::PaymentGateway

  def fixed_opts
    { :description             => "Goods from a Spree-based site", # site details...

      #:page_style             => "foobar", # merchant account can set named config
      :header_image            => "https://" + Spree::Config[:site_url] + "/images/logo.png", 
      :background_color        => "e1e1e1",  # must be hex only, six chars
      :header_background_color => "ffffff",  
      :header_border_color     => "00735a", 

      :allow_note              => true,
      :locale                  => Spree::Config[:default_locale],
      :notify_url              => 'to be done',                 # this is a callback

      :req_confirm_shipping    => false,   # for security, might make an option later
    }
  end           

  # TODO: generalise the tax and shipping calcs
  # might be able to get paypal to do some of the shipping choice and costing
  def order_opts(order)
    items = order.line_items.map do |item|
              { :name        => item.variant.product.name,
                :description => item.variant.product.description[0..120],
                :sku         => item.variant.sku,
                :qty         => item.quantity, 
                :amount      => item.price - 0.15 * item.price,   # avoid some rounding err, more needed
                :tax         => 0.15 * item.price, 
                :weight      => item.variant.weight,
                :height      => item.variant.height,
                :width       => item.variant.width,
                :depth       => item.variant.weight }
            end

    opts = { :return_url        => request.protocol + request.host_with_port + "/orders/#{order.number}/paypal_finish",
             :cancel_return_url => "http://"  + request.host_with_port + "/orders/#{order.number}/edit",
             :order_id          => order.number,
             :custom            => order.number,

             # :no_shipping     => false,
             # :address_override => false,

             :items    => items,
             :subtotal => items.map {|i| i[:amount] * i[:qty] }.sum,
             :handling => 0,
             :tax      => items.map {|i| i[:tax] * i[:qty]}.sum

             # WARNING -- don't use :ship_discount, => :insurance_offered, :insurance since 
             # they've not been tested and may trigger some paypal bugs, eg not showing order
             # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
           }

    opts[:email] = current_user.email if current_user

    opts
  end

  def all_opts(order)
    shipping_cost = NetstoresShipping::Calculator.calculate_order_shipping(order)
    opts = fixed_opts.merge(:shipping => shipping_cost).merge(order_opts order)

    # WARNING: paypal expects this sum to work (TODO: shift to AM code? and throw wobbly?)
    # however: might be rounding issues when it comes to tax, though you can capture slightly extra
    opts[:money] = opts.slice(:subtotal, :shipping, :handling, :tax).values.sum
    if opts[:money] != order.total
      raise "Ouch - precision problems: #{opts[:money]} vs #{order.total}"
    end

    [:money, :subtotal, :shipping, :handling, :tax].each {|amt| opts[amt] *= 100}
    opts[:items].each {|item| [:amount,:tax].each {|amt| item[amt] *= 100} }

    opts
  end

  def paypal_checkout
    # need build etc? at least to finalise the total?
    gateway = paypal_gateway
  
    opts = all_opts(@order)
    response = gateway.setup_authorization(opts[:money], opts)

    gateway_error(response) unless response.success?

    redirect_to (gateway.redirect_url_for response.token) 
  end

  def paypal_finish
    gateway = paypal_gateway
    opts = { :token => params[:token],
             :payer_id => params[:PayerID] }.merge all_opts(@order)
    info = gateway.details_for params[:token]
    response = gateway.authorize(opts[:money], opts)

    gateway_error(response) unless response.success?

    # now save info
    order = Order.find_by_number(params[:id])
    order.checkout.email = info.email
    order.checkout.special_instructions = info.params["note"]

    ship_address = info.address
    order_ship_address = Address.create :firstname  => info.params["first_name"],
                                        :lastname   => info.params["last_name"],
                                        :address1   => ship_address["address1"],
                                        :address2   => ship_address["address2"],
                                        :city       => ship_address["city"],
                                        :state      => State.find_by_name(ship_address["state"]),
                                        :country    => Country.find_by_iso(ship_address["country"]),
                                        :zipcode    => ship_address["zip"],
                                        :phone      => ship_address["phone"] || "(not given)"

    order.checkout.update_attributes :ship_address    => order_ship_address,
                                     :shipping_method => ShippingMethod.first          # TODO: refine/choose

    fake_card = Creditcard.new :checkout       => order.checkout,
                               :cc_type        => "visa",   # hands are tied
                               :month          => Time.now.month, 
                               :year           => Time.now.year, 
                               :first_name     => info.params["first_name"], 
                               :last_name      => info.params["last_name"],
                               :display_number => "paypal:" + info.payer_id
    payment = order.paypal_payments.create(:amount => response.params["gross_amount"].to_i || 999, 
                                           :creditcard => fake_card)

    # query - need 0 in amount for an auth? see main code
    transaction = CreditcardTxn.new( :amount => response.params["gross_amount"].to_i || 999,
                                     :response_code => response.authorization,
                                     :txn_type => CreditcardTxn::TxnType::AUTHORIZE)
    payment.creditcard_txns << transaction

    order.user = current_user

    order.save!

    order.complete  # get return of status? throw of problems??? else weak go-ahead
    session[:order_id] = nil if order.checkout_complete
    redirect_to order_url(order, :checkout_complete => true, :order_token => session[:order_token])
  end 


  def do_capture(authorization)
    response = paypal_gateway.capture((100 * authorization.amount).to_i, authorization.response_code)

    gateway_error(response) unless response.success?

    # TODO needs to be cleaned up or recast...
    payment = PaypalPayment.find(authorization.creditcard_payment_id)

    # create a transaction to reflect the capture
    payment.txns << CreditcardTxn.new( :amount        => authorization.amount,
                                       :response_code => response.authorization,
                                       :txn_type      => CreditcardTxn::TxnType::CAPTURE )
  end 


  private

  # copied from main spree code, and slightly tweaked
  def paypal_gateway
    #? return Spree::BogusGateway.new if ENV['RAILS_ENV'] == "development" and Spree::Gateway::Config[:use_bogus]
    paypal_gw = ::Gateway.find_by_name("Paypal Express UK")
    gateway_config = GatewayConfiguration.find_by_gateway_id(paypal_gw.id)
    config_options = {}
    gateway_config.gateway_option_values.each do |option_value|
      key = option_value.gateway_option.name.to_sym
      config_options[key] = option_value.value
    end
    gateway = gateway_config.gateway.clazz.constantize.new(config_options)
  end

end
