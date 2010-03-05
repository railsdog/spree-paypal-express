# aim to unpick this later
module Spree::PaypalExpress
  include ERB::Util
  include ActiveMerchant::RequiresParameters

  def paypal_checkout
    load_object
    opts = all_opts(@order, params[:payment_method_id], 'checkout')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    response = gateway.setup_authorization(opts[:money], opts)
    unless response.success?
      gateway_error(response)
      redirect_to edit_order_url(@order)
      return
    end

    redirect_to (gateway.redirect_url_for response.token, :review => payment_method.preferred_review)
  end

  def paypal_payment
    load_object
    opts = all_opts(@order,params[:payment_method_id], 'payment')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    response = gateway.setup_authorization(opts[:money], opts)
    unless response.success?
      gateway_error(response)
      redirect_to edit_order_checkout_url(@order, :step => "payment")
      return
    end

    redirect_to (gateway.redirect_url_for response.token, :review => payment_method.preferred_review)
  end

  def paypal_confirm
    load_object

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id])
    gateway = paypal_gateway

    @ppx_details = gateway.details_for params[:token]

    if @ppx_details.success?
      # now save the updated order info

      PaypalAccount.create(:email => @ppx_details.params["payer"],
                           :payer_id => @ppx_details.params["payer_id"],
                           :payer_country => @ppx_details.params["payer_country"],
                           :payer_status => @ppx_details.params["payer_status"])

      @order.checkout.special_instructions = @ppx_details.params["note"]

      #@order.update_attribute(:user, current_user)
      unless payment_method.preferred_no_shipping
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
      end
      @order.checkout.save

      if payment_method.preferred_review
        render :partial => "shared/paypal_express_confirm", :layout => true
      else
        paypal_finish
      end
    else
      gateway_error(@ppx_details)
    end
  end

  def paypal_finish
    load_object

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id], 'checkout' )
    gateway = paypal_gateway

    if Spree::Config[:auto_capture]
      ppx_auth_response = gateway.purchase((@order.total*100).to_i, opts)
      txn_type = PaypalTxn::TxnType::CAPTURE
    else
      ppx_auth_response = gateway.authorize((@order.total*100).to_i, opts)
      txn_type = PaypalTxn::TxnType::AUTHORIZE
    end

    if ppx_auth_response.success?
      paypal_account = PaypalAccount.find_by_payer_id(params[:PayerID])

      payment = @order.checkout.payments.create(:amount => ppx_auth_response.params["gross_amount"].to_f,
                                                :source => paypal_account,
                                                :payment_method_id => params[:payment_method_id])

      PaypalTxn.create(:payment => payment,
                       :txn_type => txn_type,
                       :amount => ppx_auth_response.params["gross_amount"].to_f,
                       :message => ppx_auth_response.params["message"],
                       :payment_status => ppx_auth_response.params["payment_status"],
                       :pending_reason => ppx_auth_response.params["pending_reason"],
                       :transaction_id => ppx_auth_response.params["transaction_id"],
                       :transaction_type => ppx_auth_response.params["transaction_type"],
                       :payment_type => ppx_auth_response.params["payment_type"],
                       :response_code => ppx_auth_response.params["ack"],
                       :token => ppx_auth_response.params["token"],
                       :avs_response => ppx_auth_response.avs_result["code"],
                       :cvv_response => ppx_auth_response.cvv_result["code"])


      @order.save!
      @checkout.reload
      #need to force checkout to complete state
      until @checkout.state == "complete"
        @checkout.next!
      end
      complete_checkout

      if Spree::Config[:auto_capture]
        payment.finalize!
      end

    else
      order_params = {}
      gateway_error(ppx_auth_response)
    end
  end

  private
  def fixed_opts
    if Spree::Config[:paypal_express_local_confirm].nil?
      user_action = "continue"
    else
      user_action = Spree::Config[:paypal_express_local_confirm] == "t" ? "continue" : "commit"
    end

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
      :user_action             => user_action

      # WARNING -- don't use :ship_discount, :insurance_offered, :insurance since
      # they've not been tested and may trigger some paypal bugs, eg not showing order
      # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
    }
  end
  
  # hook to override paypal site options
  def paypal_site_opts
    {}
  end

  def order_opts(order, payment_method, stage)
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


    opts = { :return_url        => request.protocol + request.host_with_port + "/orders/#{order.number}/checkout/paypal_confirm?payment_method_id=#{payment_method}",
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
      opts[:handling] = 0  # MJM Added to force elements to be generated
      opts[:shipping] = (order.ship_total*100).to_i

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
    if payment_method.preferred_no_shipping 
      { :no_shipping => true }
    else
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
  end

  def all_opts(order, payment_method, stage=nil)
    opts = fixed_opts.merge(order_opts(order, payment_method, stage)).merge(paypal_site_opts)

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
  def payment_method
    PaymentMethod.find(params[:payment_method_id])
  end

  def paypal_gateway
    payment_method.provider
  end
end
