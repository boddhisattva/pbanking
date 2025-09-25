class AddLastErrorToTransaction < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :last_error, :string, comment: "The last error message of a transaction"
  end
end
