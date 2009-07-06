# Paypal Express 

Bridge between ActiveMerchant's paypal express (PPX) gateway code and Spree


## Setup and Customization

It's currently set up to run the UK version of the gateway, but this isn't an essential detail - should be easy to change. 

  1. Start by creating/identifying the relevant class representing your locale's paypal express gateway 
     and change the +clazz+ in the migration and/or the database.

  2. Modify +lib/spree/paypal_express.rb+ to load up details for your gateway

You'll notice that I'm using Spree's gateway config mechanism. This choice is debatable: Spree is basically
set up for using one gateway at a time, whereas we probably want a main gateway plus Paypal as a backup 
choice. 



## Interaction with Spree

The bridge code receives authorization and transaction info from PPX and converts it into the Spree
equivalent. 

The payment representation isn't perfect: basically, Spree is oriented towards creditcards and some
work is needed to generalise it to other options. For now, it is a bit hacked. (See the TODO list.)


## Relationship with active merchant

This ext contains three files which are updates or extensions to current active merchant code. They are
loaded up when the extension is initialized, and will over-ride the existing gem files. The modifications
update the base protocol, eg allowing detailed order info to be passed, and supporting some of the new
options in version 57.0. 

## Testing

Get an account for Paypal's Sandbox system first. Very good testing system! 
Pity it logs you off automatically after a relatively short time period


## Status and Known issues

IMPORTANT: requires edge rails (it might work with 0.8.4)

[06Jul09] I don't know of any serious bugs or issues at present in this code, so you should be able to 
start using this without serious problems - but do note the TODO list below. 

** Temporarily, I've had to over-ride two admin views: order/show and payments/index: this will be unpicked
once Spree is generalised to support payment types other than creditcards

WARNING: there seems to be an issue with the :shipping_discount issue which causes submitted order
info to be ignored (and not displayed) - see +lib/spree/paypal_express.rb+ for more info, so I suggest
avoiding this option unless you've tested it. 



## TODO

  0. Allow easy change of locale for gateway version

  1. Move gateway config to the preferences system, to avoid interference with main gateways?

  2. Add support for accepting PPX payment at the credit card stage (important)

  3. Look at using PPX to assist in shipping method choices (or present user with a choice before
     they jump to PPX interaction)

  4. Improve payment tracking support in Spree (eg generalise beyond creditcard bias)

  5. Add some tests

  6. Get some of my code into active merchant

