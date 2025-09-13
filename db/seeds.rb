# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Create business account for Purposeful Life Inc
business_account = BusinessAccount.find_or_create_by!(
  email: 'finance@purposefullife.com'
) do |ba|
  ba.first_name = 'Purposeful'
  ba.last_name = 'Life EU-Inc'
end

puts "Created/Found business account: #{business_account.first_name} #{business_account.last_name}"

# Create bank account with specified IBAN and BIC
bank_account = BankAccount.find_or_create_by!(
  iban: 'NL02ABNA0123456789',
) do |account|
  account.business_account = business_account
  account.bic = 'BBRCIHGTXXX'
  account.balance_cents = 200000000 # Starting with 2,000,000 EUR balance
end

puts "Created/Found bank account: IBAN #{bank_account.iban}, BIC #{bank_account.bic}"

# Create sample transactions
sample_transactions = [
  {
    amount_cents: 15000, # 150.00 EUR
    currency: 'EUR',
    receiver_iban: 'DE89370400440532013000',
    recipient_name: 'Tech Solutions GmbH',
    recipient_email: 'billing@techsolutions.de',
    note: 'Software development services'
  },
  {
    amount_cents: 250050, # 2,500.50 EUR
    currency: 'EUR',
    receiver_iban: 'FR1420041010050500013M02606',
    recipient_name: 'Design Studio Paris',
    recipient_email: 'contact@designstudio.fr',
    note: 'UI/UX design consultation'
  },
  {
    amount_cents: 75000, # 750.00 EUR
    currency: 'EUR',
    receiver_iban: 'ES9121000418450200051332',
    recipient_name: 'Marketing Agency Barcelona',
    recipient_email: 'info@marketingbcn.es',
    note: 'Digital marketing campaign'
  },
  {
    amount_cents: 320000, # 3,200.00 EUR
    currency: 'EUR',
    receiver_iban: 'IT60X0542811101000000123456',
    recipient_name: 'Consulting Milano',
    recipient_email: 'admin@consultingmilano.it',
    note: 'Business strategy consultation'
  }
]

sample_transactions.each do |transaction_data|
  transaction = Transaction.create!(
    bank_account: bank_account, # source bank account for  the transaction
    amount_cents: transaction_data[:amount_cents],
    amount_currency: transaction_data[:currency],
    receiver: transaction_data[:recipient_email],
    recipient_type: 'EMAIL',
    note: transaction_data[:note]
  )

  amount_formatted = sprintf('%.2f', transaction_data[:amount_cents] / 100.0)
  puts "Created transaction: #{amount_formatted} #{transaction_data[:currency]} to #{transaction_data[:recipient_name]} (#{transaction_data[:receiver_iban]})"
end

puts "\nSeed data loaded successfully!"
puts "Total Business Accounts: #{BusinessAccount.count}"
puts "Total Bank Accounts: #{BankAccount.count}"
puts "Total Transactions: #{Transaction.count}"
