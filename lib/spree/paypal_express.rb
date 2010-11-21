module Spree::PaypalExpress
  include ERB::Util
  include ActiveMerchant::RequiresParameters

  def self.included(target)
    target.before_filter :redirect_to_paypal_express_form_if_needed, :only => [:update]
  end

  # Outbound redirect to PayPal from Cart Page
  # Not fully implmented or tested.
  #
  def paypal_checkout
    load_object
    opts = all_opts(@order, params[:payment_method_id], 'checkout')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    if Spree::Config[:auto_capture]
      response = gateway.setup_purchase(opts[:money], opts)
    else
      response = gateway.setup_authorization(opts[:money], opts)
    end

    unless response.success?
      gateway_error(response)
      redirect_to edit_order_url(@order)
      return
    end

    redirect_to (gateway.redirect_url_for response.token, :review => payment_method.preferred_review)
  end

  # Outbound redirect to PayPal from checkout payments step
  #
  def paypal_payment
    load_object
    opts = all_opts(@order,params[:payment_method_id], 'payment')
    opts.merge!(address_options(@order))
    gateway = paypal_gateway

    if Spree::Config[:auto_capture]
      response = gateway.setup_purchase(opts[:money], opts)
    else
      response = gateway.setup_authorization(opts[:money], opts)
    end

    unless response.success?
      gateway_error(response)
      redirect_to edit_order_checkout_url(@order, :step => "payment")
      return
    end

    redirect_to (gateway.redirect_url_for response.token, :review => payment_method.preferred_review)
  end

  # Inbound post from PayPal after (possible) successful completion
  #
  def paypal_confirm
    load_object

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id],  'payment')
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

  # Local call from A) Order Review Screen, or B) Automatically after paypal_confirm (no review).
  # Completes checkout & order
  #
  def paypal_finish
    load_object

    opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id], 'payment' )
    gateway = paypal_gateway

    if Spree::Config[:auto_capture]
      ppx_auth_response = gateway.purchase((@order.total*100).to_i, opts)
    else
      ppx_auth_response = gateway.authorize((@order.total*100).to_i, opts)
    end

    if ppx_auth_response.success?
      #confirm status
      case ppx_auth_response.params["payment_status"]
        when "Completed"
          txn_type = PaypalTxn::TxnType::CAPTURE
        when "Pending"
          txn_type = PaypalTxn::TxnType::AUTHORIZE
        else
          txn_type = PaypalTxn::TxnType::UNKNOWN
          Rails.logger.error "Unexpected response from PayPal Express"
          Rails.logger.error ppx_auth_response.to_yaml
      end

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

      # even with auto_capture , an Auth might be returned / forced by PPX
      if Spree::Config[:auto_capture] && txn_type == PaypalTxn::TxnType::CAPTURE
        payment.finalize!
      end

    else
      order_params = {}
      gateway_error(ppx_auth_response)

      #Failed trying to complete pending payment!
      redirect_to edit_order_checkout_url(@order, :step => "payment")
    end
  end

  private
  def redirect_to_paypal_express_form_if_needed
    return unless params[:step] == "payment"

    load_object

    payment_method = PaymentMethod.find(params[:checkout][:payments_attributes].first[:payment_method_id])

    if payment_method.kind_of?(BillingIntegration::PaypalExpress) || payment_method.kind_of?(BillingIntegration::PaypalExpressUk)
      redirect_to paypal_payment_order_checkout_url(@checkout.order, :payment_method_id => payment_method)
    end
  end

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
      price = (item.price * 100).to_i # convert for gateway
      { :name        => item.variant.product.name,
        :description => item.variant.product.description[0..120],
        :sku         => item.variant.sku,
        :qty         => item.quantity,
        :amount      => price,
        :weight      => item.variant.weight,
        :height      => item.variant.height,
        :width       => item.variant.width,
        :depth       => item.variant.weight }
    end

    #add each credit a line item to ensure totals sum up correctly
    credits = order.credits.map do |credit|
      { :name        => credit.description,
        :description => credit.description,
        :sku         => credit.id,
        :qty         => 1,
        :amount      => (credit.amount*100).to_i }
    end

    items.concat credits

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
      opts[:handling] = 0
      opts[:shipping] = (order.ship_total*100).to_i

      # overall total
      opts[:money]    = opts.slice(:subtotal, :tax, :shipping, :handling).values.sum

      opts[:callback_url] = "http://"  + request.host_with_port + "/paypal_express_callbacks/#{order.number}"
      opts[:callback_timeout] = 3
    elsif  stage == "payment"
      #use real totals are we are paying via paypal (spree checkout almost complete)
      opts[:subtotal] = ((order.item_total + order.credits.total)*100).to_i
      opts[:tax]      = (order.tax_total*100).to_i
      opts[:shipping] = (order.ship_total*100).to_i

      #hack to add float rounding difference in as handling fee - prevents PayPal from rejecting orders
      #becuase the integer totals are different from the float based total. This is temporary and will be
      #removed once Spree's currency values are persisted as integers (normally only 1c)
      opts[:handling] =  (order.total*100).to_i - opts.slice(:subtotal, :tax, :shipping).values.sum

      opts[:money] = (order.total*100).to_i
    end

    opts
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
