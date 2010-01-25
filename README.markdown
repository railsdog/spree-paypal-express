# Official PayPal Express for Spree

This is the official PayPal Express extension for Spree, based on the extension by PaulCC it has been extended to support Spree's
Billing Integrations which allows users to configure the PayPal Express gateway including API login / password and signatures fields
via the Admin UI.

This extension allows the store to use PayPal Express from two locations:

  1. Checkout Payment - When configured the PayPal Express checkout button will appear alongside the standard credit card payment
  options on the payment stage of the standard checkout. The selected shipping address and shipping method / costs are automatically
  sent to the PayPal review page (along with detailed order information).

  THIS FEATURE IS NOT YET COMPLETE
  2. Cart Checkout - Presents the PayPal checkout button on the users Cart page and redirects the user to complete all shipping / addressing
  information on PaypPal's site. This also supports PayPal's Instant Update feature to retrieve shipping options live from Spree when the user
  selects / changes their shipping address on PayPal's site.

This extension follows the documented flow for a PayPal Express Checkout, where a user is forwarded to PayPal to allow them to login and review
the order (possibly select / change shipping address and method), then the user is redirected back to Spree to confirm the order. The user
MUST confirm the order on the Spree site before the payment is authorized / captured from PayPal (and the order is transitioned to the New state).