# aim to unpick this later
module Spree::PaypalExpress
  include ERB::Util
  include ActiveMerchant::RequiresParameters

  def paypal_checkout
    load_object
    opts = all_opts(@order, 'checkout')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    response = gateway.setup_authorization(opts[:money], opts)
    unless response.success?
      gateway_error(response)
      redirect_to edit_order_url(@order)
      return
    end

    redirect_to (gateway.redirect_url_for response.token)
  end

  def paypal_payment
    load_object
    opts = all_opts(@order, 'payment')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    response = gateway.setup_authorization(opts[:money], opts)
    unless response.success?
      gateway_error(response)
      redirect_to edit_order_checkout_url(@order, :step => "payment")
      return
    end

    redirect_to (gateway.redirect_url_for response.token)
  end

  def paypal_confirm
    load_object

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order)
    gateway = paypal_gateway

    @ppx_details = gateway.details_for params[:token]

    if @ppx_details.success?
      # now save the updated order info
      @order.checkout.email = @ppx_details.email
      @order.checkout.special_instructions = @ppx_details.params["note"]

      @order.update_attribute(:user, current_user)

      ship_address = @ppx_details.address
      order_ship_address = Address.new :firstname  => @ppx_details.params["first_name"],
                                       :lastname   => @ppx_details.params["last_name"],
                                       :address1   => ship_address["address1"],
                                       :address2   => ship_address["address2"],
                                       :city       => ship_address["city"],
                                       :country    => Country.find_by_iso(ship_address["country"]),
                                       :zipcode    => ship_address["zip"],
                                       # phone is currently blanked in AM's PPX response lib
                                       :phone      => @ppx_details.params["phone"] || "(not given)"

      if (state = State.find_by_abbr(ship_address["state"]))
        order_ship_address.state = state
      else
        order_ship_address.state_name = ship_address["state"]
      end

      order_ship_address.save!

      @order.checkout.ship_address = order_ship_address
      @order.checkout.save
      render :partial => "shared/paypal_express_confirm", :layout => true
    else
      gateway_error(@ppx_details)
    end
  end

  def paypal_finish
    load_object
    #order = Order.find_by_number(params[:id])

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order)
    gateway = paypal_gateway

    if Spree::Config[:auto_capture]
      ppx_auth_response = gateway.purchase((@order.total*100).to_i, opts)
    else
      ppx_auth_response = gateway.authorize((@order.total*100).to_i, opts)
    end

    if ppx_auth_response.success?

      payment = @order.paypal_payments.create(:amount => ppx_auth_response.params["gross_amount"].to_f)

      transaction = PaypalTxn.new(:paypal_payment => payment,
                                    :gross_amount   => ppx_auth_response.params["gross_amount"].to_f,
                                    :message => ppx_auth_response.params["message"],
                                    :payment_status => ppx_auth_response.params["payment_status"],
                                    :pending_reason => ppx_auth_response.params["pending_reason"],
                                    :transaction_id => ppx_auth_response.params["transaction_id"],
                                    :transaction_type => ppx_auth_response.params["transaction_type"],
                                    :payment_type => ppx_auth_response.params["payment_type"],
                                    :ack => ppx_auth_response.params["ack"],
                                    :token => ppx_auth_response.params["token"],
                                    :avs_response => ppx_auth_response.avs_result["code"],
                                    :cvv_response => ppx_auth_response.cvv_result["code"])

      payment.paypal_txns << transaction

      @order.save!
      @checkout.reload
      until @checkout.state == "complete"
        @checkout.next!
      end

      # todo - share code
      flash[:notice] = t('order_processed_successfully')
      order_params = {:checkout_complete => true}
      order_params[:order_token] = @order.token unless @order.user
      session[:order_id] = nil if @order.checkout.completed_at

    else
      order_params = {}
      gateway_error(ppx_auth_response)
    end

    redirect_to order_url(@order, order_params)
  end

  def paypal_capture(authorization)
    ppx_response = paypal_gateway.capture((100 * authorization.gross_amount).to_i, authorization.transaction_id)

    if ppx_response.success?
      payment = authorization.paypal_payment

      transaction = PaypalTxn.new(:paypal_payment => payment,
                                    :gross_amount   => ppx_response.params["gross_amount"].to_f,
                                    :message => ppx_response.params["message"],
                                    :payment_status => ppx_response.params["payment_status"],
                                    :pending_reason => ppx_response.params["pending_reason"],
                                    :transaction_id => ppx_response.params["transaction_id"],
                                    :transaction_type => ppx_response.params["transaction_type"],
                                    :payment_type => ppx_response.params["payment_type"],
                                    :ack => ppx_response.params["ack"],
                                    :token => ppx_response.params["token"],
                                    :avs_response => ppx_response.avs_result["code"],
                                    :cvv_response => ppx_response.cvv_result["code"])

      payment.paypal_txns << transaction

      payment.save
    else
      gateway_error(ppx_response)
    end
  end

  def paypal_refund(authorization, amount=nil)
    ppx_response = paypal_gateway.credit(amount.nil? ? (100 * authorization.gross_amount).to_i : (100 * amount).to_i, authorization.transaction_id)

    if ppx_response.success?
      payment = authorization.paypal_payment

      transaction = PaypalTxn.new(:paypal_payment => payment,
                                    :gross_amount   => ppx_response.params["gross_refund_amount"].to_f,
                                    :message => ppx_response.params["message"],
                                    :payment_status => "Refunded",
                                    :pending_reason => ppx_response.params["pending_reason"],
                                    :transaction_id => ppx_response.params["refund_transaction_id"],
                                    :transaction_type => ppx_response.params["transaction_type"],
                                    :payment_type => ppx_response.params["payment_type"],
                                    :ack => ppx_response.params["ack"],
                                    :token => ppx_response.params["token"],
                                    :avs_response => ppx_response.avs_result["code"],
                                    :cvv_response => ppx_response.cvv_result["code"])

      payment.paypal_txns << transaction

      payment.save
    else
      gateway_error(ppx_response)
    end
  end

  private
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

      # WARNING -- don't use :ship_discount, :insurance_offered, :insurance since
      # they've not been tested and may trigger some paypal bugs, eg not showing order
      # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
    }
  end

  def order_opts(order, stage)
    items = order.line_items.map do |item|
              tax = paypal_variant_tax(item.price, item.variant)
              price = (item.price * 100).to_i # convert for gateway
              tax   = (tax        * 100).to_i # truncate the tax slice
              { :name        => item.variant.product.name,
                :description => item.variant.product.description[0..120],
                :sku         => item.variant.sku,
                :qty         => item.quantity,
                :amount      => price - tax,
                :tax         => tax,
                :weight      => item.variant.weight,
                :height      => item.variant.height,
                :width       => item.variant.width,
                :depth       => item.variant.weight }
            end


    opts = { :return_url        => request.protocol + request.host_with_port + "/orders/#{order.number}/checkout/paypal_confirm",
             :cancel_return_url => "http://"  + request.host_with_port + "/orders/#{order.number}/edit",
             :order_id          => order.number,
             :custom            => order.number,
             :items             => items
           }

    if stage == "checkout"
      # recalculate all totals here as we need to ignore shipping & tax because we are checking-out via paypal (spree checkout not started)

      # get the main totals from the items (already *100)
      opts[:subtotal] = opts[:items].map {|i| i[:amount] * i[:qty] }.sum
      opts[:tax]      = opts[:items].map {|i| i[:tax]    * i[:qty] }.sum

      # overall total
      opts[:money]    = opts.slice(:subtotal, :tax, :shipping, :handling).values.sum

      opts[:money] = (order.total*100).to_i

      opts[:callback_url] = "http://"  + request.host_with_port + "/paypal_express_callbacks/#{order.number}"
      opts[:callback_timeout] = 3

    elsif  stage == "payment"
      #use real totals are we are paying via paypal (spree checkout almost complete)
      opts[:subtotal] = (order.item_total*100).to_i
      opts[:tax]      = 0 # BQ : not sure what to do here
      opts[:shipping] = (order.ship_total*100).to_i
      opts[:handling] = 0 # BQ : not sure what to do here

      # overall total
      opts[:money]    = opts.slice(:subtotal, :tax, :shipping, :handling).values.sum

      opts[:money] = (order.total*100).to_i
    end

    opts
  end

  # hook for supplying tax amount for a single unit of a variant
  # expects the sale price from the line_item and the variant itself, since
  #   line_item price and variant price can diverge in time
  def paypal_variant_tax(sale_price, variant)
    0.0
  end

  def address_options(order)
    {
      :no_shipping => false,
      :address_override => true,
      :address => {
        :name       => "#{order.ship_address.firstname} #{order.ship_address.lastname}",
        :address1   => order.ship_address.address1,
        :address2   => order.ship_address.address2,
        :city       => order.ship_address.city,
        :state      => order.ship_address.state.nil? ? order.ship_address.state_name.to_s : order.ship_address.state.abbr,
        :country    => order.ship_address.country.iso,
        :zip        => order.ship_address.zipcode,
        :phone      => order.ship_address.phone
      }
    }
  end

  def all_opts(order, stage=nil)
    opts = fixed_opts.merge(order_opts(order, stage))#.
              # merge(paypal_site_options                order) BQ

    if stage == "payment"
      opts.merge! flat_rate_shipping_and_handling_options(order, stage)
    end

    # suggest current user's email or any email stored in the order
    opts[:email] = current_user ? current_user.email : order.checkout.email

    opts
  end

  # hook to allow applications to load in their own shipping and handling costs
  def flat_rate_shipping_and_handling_options(order, stage)
    # max_fallback = 0.0
    # shipping_options = ShippingMethod.all.map do |shipping_method|
    #       max_fallback = shipping_method.fallback_amount if shipping_method.fallback_amount > max_fallback
    #           { :name       => "#{shipping_method.id}",
    #             :label       => "#{shipping_method.name} - #{shipping_method.zone.name}",
    #             :amount      => (shipping_method.fallback_amount*100) + 1,
    #             :default     => shipping_method.is_default }
    #         end
    #
    #
    # default_shipping_method = ShippingMethod.find(:first, :conditions => {:is_default => true})
    #
    # opts = { :shipping_options  => shipping_options,
    #          :max_amount  => (order.total + max_fallback)*100
    #        }
    #
    # opts[:shipping] = (default_shipping_method.nil? ? 0 : default_shipping_method.fallback_amount) if stage == "checkout"
    #
    # opts
    {}
  end

  def gateway_error(response)
    text = response.params['message'] ||
           response.params['response_reason_text'] ||
           response.message
    msg = "#{I18n.t('gateway_error')} ... #{text}"
    logger.error(msg)
    flash[:error] = msg
  end

  # create the gateway from the supplied options
  def paypal_gateway
    integration = BillingIntegration.find(params[:integration_id]) if params.key? :integration_id
    integration ||= BillingIntegration.current

    gateway = integration.provider
  end
end
