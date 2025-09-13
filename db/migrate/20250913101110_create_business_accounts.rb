class CreateBusinessAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :business_accounts do |t|
      t.string :first_name, null: false, comment: "The first name of the business account"
      t.string :last_name, null: false, comment: "The last name of the business account"
      t.string :email, null: false, comment: "The email of the business account"
      t.timestamps
    end

    add_index :business_accounts, :email, unique: true
  end
end
