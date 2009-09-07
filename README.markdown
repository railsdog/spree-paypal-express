# Paypal Express for Spree

Bridge between ActiveMerchant's Paypal Express (henceforth PPX) gateway code and Spree


## Setup and Customization


  1. Start by identifying the relevant class representing your locale's paypal express gateway

  2. If there isn't one, then you can easily create one and patch it in. You can drop it in
     the directory +lib/active_merchant/billing/gateways/+ in an extension - probably best in your
     +site+ extension - and make sure it is loaded with the following line (suitably modified) in 
     your extension activation code :

     require File.join(SiteExtension.root, "lib", "active_merchant", "billing", "gateways", "paypal_express_narnia.rb")

     See how I've handled the UK gateway customization in this extension for more info. 

  3. Over-ride the hook +paypal_site_options+ in the OrdersController (eg with a +class_eval+ in your
     +site+ extension's activation code) so that it returns a _hash_ with at least the following
     fields. The hook is sent the current order value, in case it is needed.

      * +:ppx_class+  -- name of the actual gateway class
      * +:login+      -- the merchant's login email address
      * +:password+   -- the merchant's Paypal API Credentials Password
      * +:signature+  -- the merchant's Paypal API Credentials signature string
 
  4. You can also over-ride other PPX settings from this hook, eg the +:description+ string 
     attached to transactions, or the colour scheme and logo, or ... (see +lib/spree/paypal_express.rb+
     for more information. 

  5. Over-ride the hook +paypal_variant_tax+ to calculate the tax amount for a single unit of a
     variant. The hook is passed the +price+ from the containing +line_item+, plus the variant
     itself. Note that the line_item price and the variant price can diverge (the former won't be
     changed if the administrator changes the variant price), and Spree usually ignores the 
     variant price after the line_item has been created, so you probably want to calculate tax 
     from the line_item price. You should return a floating point number here. The hook is
     located in the OrdersController.

  6. Over-ride the hook +paypal_shipping_and_handling_costs+ (also in the OrdersController), to 
     determine a shipping and handling estimate for the order. See below for a discussion of 
     shipping issues and how they affect PPX. 

     The hook is sent the order value, and must return a _hash_ containing (at least) a 
     :shipping and a :handling value (both floats), which are the total costs for the order.




## Interaction with Spree

The bridge code receives authorization and transaction info from PPX and converts it into the Spree
equivalent. 

The payment representation isn't perfect: basically, Spree is oriented towards creditcards and some
work is needed to generalise it to other options. For now, it is a bit hacked. (See the TODO list.)


## Relationship with Active Merchant

This extension contains three files which are updates or extensions to current active merchant code. They are
loaded up when the extension is initialized, and will over-ride the existing gem files. The modifications
update the base protocol, eg allowing detailed order info to be passed, and supporting _some_ (not all)
of the new options in version 57.0. 

## Testing

Get an account for Paypal's Sandbox system first. Very good testing system! 
Pity it logs you off automatically after a relatively short time period


## Status and Known issues

IMPORTANT: requires spree version 0.8.5 or later (there's a tag in the repo for earlier versions, but it needs some bug patching now)

[15Jul09] I don't know of any serious bugs or issues at present in this code, so you should be able to 
start using this without serious problems - but do note the TODO list below. 

Temporarily, I've had to over-ride two admin views: order/show and payments/index: this will be unpicked
once Spree is generalised to support payment types other than creditcards

WARNING: there seems to be an issue with the :shipping_discount issue which causes submitted order
info to be ignored (and not displayed - probably because the PPX addition checking doesn't tally).
See +lib/spree/paypal_express.rb+ for more info. I suggest avoiding this option unless you've 
tested it carefully. The insurance options are also not tested yet.



## Hooks

These were discussed in the customization section above, but for reference, they are:

  * +paypal_variant_tax(sale_price, variant)+
  * +paypal_site_opts(order)+
  * +paypal_shipping_and_handling_costs(order)+


## Shipping Issues

It is important to note that Spree won't have selected a shipping method when the PPX process
is started. My sites only have a single shipping method, so I can get away with defaulting to
that method and using that for calculations. It also means that I've not written any code yet 
for selecting from applicable methods etc etc.

Beware that this code does make some big assumptions about shipping. In particular, it AVOIDS 
use of the Spree shipping calcs, effectively performing its own calcs (via the hook), but then 
assigning the first shipping method at the end, just so order display will work. This stuff 
is ok when there's a single shipping option defined (like me), but will need work if you have 
more options. 

Note that PPX allows you to capture up to 115% of the original authorized amount: this could 
allow some flexibility in shipping choices, eg you could add a stage after return from PPX 
which asks for a shipping choice and confirms the final amount to be captured.

It seems that PPX might have support for choosing a shipping method on its screens, but I 
have not tried to use this yet.

## TODO

  0. Add support for accepting PPX payment at the credit card stage (important)

  1. Look at using PPX to assist in shipping method choices (or present user with a choice before
     they jump to PPX interaction)

  2. Improve payment tracking support in Spree (eg generalise beyond creditcard bias)

  3. Add some tests

  4. Get some of my code into active merchant

  5. Double-check implementation of the full PPX process

  6. Look at shipping method selection integration 
