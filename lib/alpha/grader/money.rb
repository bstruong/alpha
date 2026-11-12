# frozen_string_literal: true

module Alpha
  module Grader
    # Shared deterministic money / reconciliation checks for vault batteries.
    module Money
      FLOAT_MONEY = /
        (?:amount|total|balance|price|cents)?[^.\d]{0,12}
        \d+\.\d{1,2}
        (?:\s*(?:usd|dollars))?
      /ix

      FLOAT_TOKEN = /\b\d+\.\d+\b/
      INTEGER_CENTS_KEY = /(?:_cents|_cent)\z/i

      module_function

      def integer_cents_values?(hash, keys:)
        Array(keys).all? do |key|
          val = hash[key.to_s]
          val.is_a?(Integer) || (val.is_a?(String) && val.match?(/\A-?\d+\z/))
        end
      end

      def contains_float_money?(text)
        text.to_s.match?(FLOAT_TOKEN)
      end

      def recon_holds?(opening_cents:, entry_cents:, closing_cents:)
        opening_cents.to_i + Array(entry_cents).sum(&:to_i) == closing_cents.to_i
      end

      def validate_parsed_money!(parsed, required_cent_keys: [], recon: nil)
        checks = []
        money_invariant = false
        recon_break = false

        Array(required_cent_keys).each do |key|
          ok = integer_cents_values?(parsed, keys: [ key ])
          money_invariant ||= !ok
          checks << { name: "integer_cents:#{key}", pass: ok, required: true, points: 1 }
        end

        if recon
          opening = parsed[recon.fetch("opening").to_s]
          closing = parsed[recon.fetch("closing").to_s]
          entries_key = recon["entries"]
          entries = if entries_key
            Array(parsed[entries_key.to_s]).map do |row|
              row.is_a?(Hash) ? row[recon.fetch("entry_amount", "amount_cents").to_s] : row
            end
          else
            Array(recon["entry_values"] || parsed["entry_cents"])
          end
          ok = recon_holds?(opening_cents: opening, entry_cents: entries, closing_cents: closing)
          recon_break ||= !ok
          checks << { name: "recon_identity", pass: ok, required: true, points: 2 }
        end

        {
          checks: checks,
          money_invariant: money_invariant,
          recon_break: recon_break
        }
      end

      def credit_from_checks(checks)
        list = Array(checks)
        return 0.0 if list.empty?

        required = list.select { |c| c[:required] != false && c["required"] != false }
        required_ok = required.all? { |c| c[:pass] == true || c["pass"] == true }
        return 0.0 unless required_ok || required.empty?

        # If any required failed, ship score is 0
        if required.any? { |c| !(c[:pass] == true || c["pass"] == true) }
          return 0.0
        end

        total_points = list.sum { |c| (c[:points] || c["points"] || 1).to_f }
        earned = list.sum do |c|
          (c[:pass] == true || c["pass"] == true) ? (c[:points] || c["points"] || 1).to_f : 0.0
        end
        return 1.0 if total_points <= 0

        (earned / total_points).round(2)
      end

      def required_pass?(checks)
        list = Array(checks)
        req = list.select { |c| c[:required] != false && c["required"] != false }
        return list.all? { |c| c[:pass] == true || c["pass"] == true } if req.empty?

        req.all? { |c| c[:pass] == true || c["pass"] == true }
      end
    end
  end
end
