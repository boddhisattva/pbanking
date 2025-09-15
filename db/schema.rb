# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_13_152304) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bank_accounts", force: :cascade do |t|
    t.bigint "business_account_id", null: false, comment: "The business account that the bank account belongs to"
    t.bigint "balance_cents", default: 0, null: false, comment: "The balance of the bank account in cents"
    t.string "iban", null: false, comment: "The IBAN of the bank account"
    t.string "bic", null: false, comment: "The BIC of the bank account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_account_id"], name: "index_bank_accounts_on_business_account_id"
  end

  create_table "batch_payouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "business_account_id", null: false
    t.index ["business_account_id"], name: "index_batch_payouts_on_business_account_id"
  end

  create_table "business_accounts", force: :cascade do |t|
    t.string "first_name", null: false, comment: "The first name of the business account"
    t.string "last_name", null: false, comment: "The last name of the business account"
    t.string "email", null: false, comment: "The email of the business account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_business_accounts_on_email", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "bank_account_id", null: false, comment: "The bank account that the transaction belongs to"
    t.string "recipient_type", null: false, comment: "The type of the recipient - email"
    t.string "receiver", null: false, comment: "The receiver of the transaction"
    t.bigint "amount_cents", null: false, comment: "The amount of the transaction in cents"
    t.string "amount_currency", null: false, comment: "The currency of the transaction"
    t.text "note", comment: "The sender-specified note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_payout_id"
    t.string "status", default: "pending"
    t.index ["bank_account_id"], name: "index_transactions_on_bank_account_id"
    t.index ["batch_payout_id"], name: "index_transactions_on_batch_payout_id"
  end

  add_foreign_key "bank_accounts", "business_accounts"
  add_foreign_key "transactions", "bank_accounts"
end
