# Bulk Payouts through Paypal

Paypal has a number of customers, they fall into two key category types - those with personal accounts & ones with business accounts. Those having business accounts need to make a large number of transfers periodically for paying the salaries of a lot of employees each month.

# Your goal

Write an API to receive a bulk payout request from a single Business account and also ensure the following -
1. Verify the validity of the request: whether the customer has sufficient funds for all the transfers in the request.

If the customer does not have enough funds, handle the request appropriately.

2. Handle the transfers according to following scenarios
- Success response
- Failure response(s)

Use the `bulk_payout_request1.json` as input for sample transfers that are received to the Bulk Payout API that you'd  as input & which you need to process.

Create a Bank account with a balance through a seeds file for a
a sample business account you choose with a balance of 2,000,000 Euros

Develop a complete API based solution that handles different payment scenarios appropriately.

# Assumptions

- Let's assume for the given exercise payouts are possible only through the recipient email with regards to one's Paypal account.
