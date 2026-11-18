# app/services/ingestion/parse_spreadsheet_service.rb
require "roo"

module Ingestion
  class ParseSpreadsheetService
    SUPPORTED_CURRENCIES = %w[USD EUR GBP JPY CHF].freeze

    def self.call(file_path:, target_tenant:, target_account: nil)
      new(file_path: file_path, target_tenant: target_tenant, target_account: target_account).call
    end

    def initialize(file_path:, target_tenant:, target_account: nil)
      @file_path = file_path
      @target_tenant = target_tenant
      @target_account = target_account
    end

    def call
      spreadsheet = Roo::Spreadsheet.open(@file_path, extension: :xlsx)
      spreadsheet.default_sheet = spreadsheet.sheets.first

      header = spreadsheet.row(1).map { |h| h.to_s.strip.underscore.to_sym }

      (2..spreadsheet.last_row).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]

        next if row[:tenant].blank? || row[:account].blank?

        # 1. Enforce Tenant Isolation: Skip rows that do not belong to the target authenticated tenant
        row_tenant_slug = row[:tenant].to_s.strip.downcase
        next unless row_tenant_slug == @target_tenant.slug

        # 2. Match or locate account strictly scoped to target_tenant
        account_number = row[:account].to_s.strip
        if @target_account
          next unless account_number == @target_account.account_number
          account = @target_account
        else
          account = @target_tenant.accounts.find_or_create_by!(account_number: account_number) do |a|
            a.business_unit = normalize_business_unit(row[:business_unit])
          end
        end

        currency = parse_currency(row[:currency], row[:amount])
        amount_cents = parse_amount_cents(row[:amount], currency)

        raw_line, newly_inserted = RawStatementLine.ingest_safely!(
          tenant: @target_tenant,
          account: account,
          source_id: row[:source_id].to_s.strip.presence,
          currency: currency,
          amount_cents: amount_cents,
          value_date: parse_value_date(row[:value_date]),
          posting_ts: parse_posting_ts(row[:posting_ts]),
          category: row[:category].to_s.strip.presence,
          description: row[:description].to_s.strip.presence
        )

        Reconciliation::ProcessLineService.new(raw_line).call if newly_inserted
      end
    end

    private

    def normalize_business_unit(raw_bu)
      return nil if raw_bu.blank?

      raw_bu.to_s.tr("_", " ").squish.split.map do |word|
        %w[apac emea uk us].include?(word.downcase) ? word.upcase : word.capitalize
      end.join(" ")
    end

    def parse_currency(raw_currency, raw_amount)
      code = raw_currency.to_s.strip.upcase
      return code if SUPPORTED_CURRENCIES.include?(code)

      case raw_amount.to_s
      when /€/ then "EUR"
      when /£/ then "GBP"
      when /¥/ then "JPY"
      else "USD"
      end
    end

    def parse_amount_cents(raw_amount, currency)
      cleaned = raw_amount.to_s.gsub(/[^\d.\-]/, "")
      raise ArgumentError, "Invalid amount format" if cleaned.blank?

      Monetize.parse!(cleaned, currency).cents
    end

    def parse_value_date(raw_date)
      case raw_date
      when Date, DateTime, Time
        raw_date.to_date
      when String
        str = raw_date.strip
        if str.match?(%r{\A\d{2}/\d{2}/\d{4}\z})
          Date.strptime(str, "%d/%m/%Y")
        else
          Date.parse(str) rescue nil
        end
      else
        nil
      end
    end

    def parse_posting_ts(raw_ts)
      case raw_ts
      when DateTime, Time
        raw_ts.in_time_zone
      when Date
        raw_ts.to_time.in_time_zone
      when String
        Time.zone.parse(raw_ts.strip)
      else
        Time.current
      end
    end
  end
end
