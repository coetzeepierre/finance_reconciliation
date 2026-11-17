# app/services/ingestion/parse_csv_service.rb
require "csv"

module Ingestion
  class ParseCsvService
    SUPPORTED_CURRENCIES = %w[USD EUR GBP JPY CHF].freeze

    def self.call(file_path)
      new(file_path).call
    end

    def initialize(file_path)
      @file_path = file_path
    end

    def call
      CSV.foreach(@file_path, headers: true, header_converters: :symbol) do |row|
        next if row[:tenant].blank? || row[:account].blank?

        tenant = Tenant.find_or_create_by!(slug: row[:tenant].strip.downcase) do |t|
          t.name = row[:tenant].strip.titleize
        end

        account = tenant.accounts.find_or_create_by!(account_number: row[:account].strip) do |a|
          a.business_unit = normalize_business_unit(row[:business_unit])
        end

        currency = parse_currency(row[:currency], row[:amount])
        amount_cents = parse_amount_cents(row[:amount], currency)

        raw_line, newly_inserted = RawStatementLine.ingest_safely!(
          tenant: tenant,
          account: account,
          source_id: row[:source_id].to_s.strip.presence,
          currency: currency,
          amount_cents: amount_cents,
          value_date: parse_value_date(row[:value_date]),
          posting_ts: Time.zone.parse(row[:posting_ts].to_s.strip),
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
      raise ArgumentError, "Unparseable amount: #{raw_amount.inspect}" if cleaned.blank?

      Monetize.parse!(cleaned, currency).cents
    end

    def parse_value_date(raw_date)
      str = raw_date.to_s.strip
      if str.match?(%r{\A\d{2}/\d{2}/\d{4}\z})
        Date.strptime(str, "%d/%m/%Y")
      else
        Date.iso8601(str)
      end
    end
  end
end
