# aim to unpick this later
module Spree::PaypalExpress
  include ERB::Util
  include Spree::PaymentGateway
  include ActiveMerchant::RequiresParameters 


  def fixed_opts
    { :description             => "Goods from #{Spree::Config[:site_name]}", # site details...

      #:page_style             => "foobar", # merchant account can set named config
      :header_image            => "https://" + Spree::Config[:site_url] + "/images/logo.png", 
      :background_color        => "ffffff",  # must be hex only, six chars
      :header_background_color => "ffffff",  
      :header_border_color     => "ffffff", 

      :allow_note              => true,
      :locale                  => Spree::Config[:default_locale],
      :notify_url              => 'to be done',                 # this is a callback, not tried it yet

      :req_confirm_shipping    => false,   # for security, might make an option later

      # :no_shipping     => false,
      # :address_override => false,

      # WARNING -- don't use :ship_discount, :insurance_offered, :insurance since 
      # they've not been tested and may trigger some paypal bugs, eg not showing order
      # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
    }
  end           

  # TODO: generalise the tax and shipping calcs
  # might be able to get paypal to do some of the shipping choice and costing
  def order_opts(order)
    items = order.line_items.map do |item|
              tax = paypal_variant_tax(item.price, item.variant)
              { :name        => item.variant.product.name,
                :description => item.variant.product.description[0..120],
                :sku         => item.variant.sku,
                :qty         => item.quantity, 
                :amount      => item.price - tax,   # TODO: test if ok on multi-qty orders
                :tax         => tax,
                :weight      => item.variant.weight,
                :height      => item.variant.height,
                :width       => item.variant.width,
                :depth       => item.variant.weight }
            end

    opts = { :return_url        => request.protocol + request.host_with_port + "/orders/#{order.number}/paypal_finish",
             :cancel_return_url => "http://"  + request.host_with_port + "/orders/#{order.number}/edit",
             :order_id          => order.number,
             :custom            => order.number,

             :items    => items,
             :subtotal => items.map {|i| i[:amount] * i[:qty] }.sum,
             :tax      => items.map {|i| i[:tax] * i[:qty]}.sum

           }
    opts
  end

  # hook for supplying tax amount for a single unit of a variant
  # expects the sale price from the line_item and the variant itself, since
  #   line_item price and variant price can diverge in time
  def paypal_variant_tax(sale_price, variant) 
    0.0
  end 

  # hook for easy site configuration, needs to return a hash
  # you probably wanto over-ride the description option here, maybe the colours and logo
  def paypal_site_options(order) 
    {}
  end

  # hook to allow applications to load in their own shipping and handling costs
  # eg might want to estimate from cheapest shipping option and rely on ability to
  #   claim an extra 15% in the final auth
  def paypal_shipping_and_handling_costs(order)
    {}
  end

  def all_opts(order)

    opts = fixed_opts.merge(order_opts                         order).
                      merge({ :shipping => 0, :handling => 0 }      ).
                      merge(paypal_shipping_and_handling_costs order).
                      merge(paypal_site_options                order)

    # add the shipping and handling estimates to spree's order total
    # (spree won't add them yet, since we've not officially chosen the shipping method)
    spree_total = order.total + opts[:shipping] + opts[:handling]

    # paypal expects this sum to work out (TODO: shift to AM code? and throw wobbly?)
    # there might be rounding issues when it comes to tax, though you can capture slightly extra
    opts[:money] = opts.slice(:subtotal, :tax, :shipping, :handling).values.sum
    if opts[:money] != spree_total
      raise "Ouch - precision problems: #{opts[:money]} vs #{spree_total}"
    end

    # prepare the numbers for the gateway
    [:money, :subtotal, :shipping, :handling, :tax].each {|amt| opts[amt] *= 100}
    opts[:items].each {|item| [:amount,:tax].each {|amt| item[amt] *= 100} }

    # suggest current user's email or any email stored in the order
    opts[:email] = current_user ? current_user.email : order.checkout.email

    opts
  end

  def paypal_checkout
    opts = all_opts(@order)
    gateway = paypal_gateway
    response = gateway.setup_authorization(opts[:money], opts)

    gateway_error(response) unless response.success?

    redirect_to (gateway.redirect_url_for response.token) 
  end

  def paypal_finish
    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order)
    gateway = paypal_gateway
    info = gateway.details_for params[:token]
    response = gateway.authorize(opts[:money], opts)

    gateway_error(response) unless response.success?

    # now save info
    order = Order.find_by_number(params[:id])
    order.checkout.email = info.email
    order.checkout.special_instructions = info.params["note"]

    ship_address = info.address
    order_ship_address = Address.new :firstname  => info.params["first_name"],
                                     :lastname   => info.params["last_name"],
                                     :address1   => ship_address["address1"],
                                     :address2   => ship_address["address2"],
                                     :city       => ship_address["city"],
                                     :country    => Country.find_by_iso(ship_address["country"]),
                                     :zipcode    => ship_address["zip"],
                                     :phone      => ship_address["phone"] || "(not given)"

    if (state = State.find_by_name(ship_address["state"]))
      order_ship_address.state = state
    else
      order_ship_address.state_name = ship_address["state"]
    end
    order_ship_address.save!

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

    flash[:notice] = t('order_processed_successfully')
    order_params = {:checkout_complete => true}
    order_params[:order_token] = @order.token unless @order.user
    session[:order_id] = nil if @order.checkout.completed_at
    redirect_to order_url(@order, order_params) 
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

  # create the gateway from the supplied options
  def paypal_gateway
    gw_defaults = { :ppx_class => "ActiveMerchant::Billing::PaypalExpressUkGateway" }
    gw_opts     = gw_defaults.merge(paypal_site_options @order)
 
    begin 
      requires!(gw_opts, :ppx_class, :login, :password, :signature)
    rescue ArgumentError => err
      raise ArgumentError.new(<<"EOM" + err.message)
Problem with configuring Paypal Express Gateway:
You need to ensure that hook "paypal_site_options" sets values for login, password, and signature.
It currently produces: #{paypal_site_options.inspect}
EOM
    end 

    gateway = gw_opts[:ppx_class].constantize.new(gw_opts)
  end
end
