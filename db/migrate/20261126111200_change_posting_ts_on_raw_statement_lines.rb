class ChangePostingTsOnRawStatementLines < ActiveRecord::Migration[8.1]
  def change
    change_column :raw_statement_lines, :posting_ts, :datetime
  end
end
