# app/services/ingestion/parse_statement_file_service.rb
require "roo"

module Ingestion
  class ParseStatementFileService
    SUPPORTED_CURRENCIES = %w[USD EUR GBP JPY CHF].freeze

    def self.call(file_path:, target_tenant:, target_account: nil, original_filename: nil)
      new(
        file_path: file_path,
        target_tenant: target_tenant,
        target_account: target_account,
        original_filename: original_filename
      ).call
    end

    def initialize(file_path:, target_tenant:, target_account: nil, original_filename: nil)

      raise ArgumentError, "Missing file to process" if file_path.blank?

      @file_path = file_path
      @target_tenant = target_tenant
      @target_account = target_account
      @original_filename = original_filename || file_path
    end

    def call
      Rails.logger.info "[Ingestion] Starting statement file ingestion for tenant '#{@target_tenant.slug}' (File: #{@original_filename})"

      ext = File.extname(@original_filename).delete(".").downcase.to_sym
      # Roo can auto-detect CSV, XLS, and XLSX by extension:
      spreadsheet = Roo::Spreadsheet.open(@file_path, extension: ext)
      spreadsheet.default_sheet = spreadsheet.sheets.first

      header = spreadsheet.row(1).map { |h| h.to_s.strip.underscore.to_sym }

      (2..spreadsheet.last_row).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]

        next if row[:tenant].blank? || row[:account].blank?

        # 1. Enforce Tenant Isolation: Skip rows that do not belong to the target authenticated tenant
        row_tenant_slug = row[:tenant].to_s.strip.downcase
        unless row_tenant_slug == @target_tenant.slug
          Rails.logger.debug "[Ingestion] Skipping row belonging to external tenant '#{row_tenant_slug}' (Target: #{@target_tenant.slug})"
          next
        end

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
          posting_ts: parse_value_date(row[:posting_ts]),
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

      # Monetize.parse! handles currency subunit exponents (0 for JPY, 2 for USD/EUR/GBP)
      Monetize.parse!(cleaned, currency).cents
    end

    def parse_value_date(raw_date)
      case raw_date
      when Date, DateTime, Time
        raw_date.to_date
      when String
        str = raw_date.strip
        return nil if str.blank?

        if str.match?(%r{\A\d{2}/\d{2}/\d{4}\z})
          Date.strptime(str, "%d/%m/%Y")
        else
          begin
            Date.iso8601(str)
          rescue ArgumentError, Date::Error
            Date.parse(str)
          end
        end
      else
        raise ArgumentError, "Unparseable date: #{raw_date.inspect}"
      end
    rescue ArgumentError, Date::Error
      raise ArgumentError, "Unparseable date: #{raw_date.inspect}"
    end
  end
end
