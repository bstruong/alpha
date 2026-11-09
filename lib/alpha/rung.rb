# frozen_string_literal: true

module Alpha
  # Capability ladder rungs L0 (recipe) … L4 (multi-step).
  module Rung
    ORDER = %w[L0 L1 L2 L3 L4].freeze

    module_function

    def normalize(value)
      return nil if value.nil? || value.to_s.strip.empty?

      key = value.to_s.strip.upcase
      key = "L#{key}" if key.match?(/\A[0-4]\z/)
      raise ArgumentError, "Unknown rung #{value.inspect} (expected L0–L4)" unless ORDER.include?(key)

      key
    end

    def index(value)
      ORDER.index(normalize(value))
    end

    def <=(a, b)
      index(a) <= index(b)
    end

    def max(*values)
      values.compact.map { |v| normalize(v) }.max_by { |v| index(v) }
    end

    def compare(a, b)
      index(a) <=> index(b)
    end
  end
end
