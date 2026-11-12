# frozen_string_literal: true

require "yaml"

module Alpha
  # Loads alpha-lab's versioned statistical protocol and computes uncertainty.
  # Scaffolding for Phase 7 — does not grant Unattended routing authority.
  class StatisticalProtocol
    SCHEMA = "alpha.statistical_protocol.v1"
    DEFAULT_RELATIVE = File.join("schemas", "statistical-protocol.v1.yml")

    def self.load(path = nil)
      path ||= File.join(Alpha.config.root, DEFAULT_RELATIVE)
      return null_protocol unless File.file?(path)

      data = YAML.safe_load_file(path) || {}
      return null_protocol unless data["schema"] == SCHEMA

      new(data, path: path)
    rescue Psych::Exception
      null_protocol
    end

    def self.null_protocol
      new(
        {
          "schema" => SCHEMA,
          "protocol_id" => "alpha.builtin.single_trial",
          "protocol_version" => "0.0.0-scaffold",
          "unattended_enabled" => false,
          "uncertainty" => {
            "method" => "wilson_score_interval",
            "confidence_level" => 0.95
          },
          "sample_size" => {
            "min_effective_trials_unattended" => 24
          },
          "counts" => {
            "separate_coverage_from_reliability" => true
          }
        },
        path: nil
      )
    end
    private_class_method :null_protocol

    # Two-sided Wilson score interval. Returns [lo, hi] or nil when n == 0.
    def self.wilson_interval(successes, total, z: 1.959963984540054)
      n = total.to_i
      return nil if n <= 0

      p = successes.to_f / n
      z2 = z * z
      denom = 1.0 + (z2 / n)
      center = (p + (z2 / (2.0 * n))) / denom
      half = (z / denom) * Math.sqrt((p * (1.0 - p) / n) + (z2 / (4.0 * n * n)))
      [[center - half, 0.0].max, [center + half, 1.0].min]
    end

    attr_reader :data, :path

    def initialize(data, path:)
      @data = data
      @path = path
    end

    def protocol_id
      data["protocol_id"]
    end

    def protocol_version
      data["protocol_version"]
    end

    def unattended_enabled?
      data["unattended_enabled"] == true
    end

    def uncertainty_method
      data.dig("uncertainty", "method") || "wilson_score_interval"
    end

    def confidence_level
      data.dig("uncertainty", "confidence_level") || 0.95
    end

    def min_effective_trials_unattended
      data.dig("sample_size", "min_effective_trials_unattended").to_i
    end

    def separate_coverage_from_reliability?
      data.dig("counts", "separate_coverage_from_reliability") != false
    end

    def statistical_sufficiency(valid_trial_count:)
      n = valid_trial_count.to_i
      return "not_evaluated" if n <= 0
      return "inadequate_for_unattended" if n < min_effective_trials_unattended

      "meets_min_sample_size"
    end

    def payload_fragment(valid_trials:, successes:)
      interval = self.class.wilson_interval(successes, valid_trials)
      {
        "schema" => SCHEMA,
        "protocol_id" => protocol_id,
        "protocol_version" => protocol_version,
        "unattended_enabled" => unattended_enabled?,
        "uncertainty" => {
          "method" => uncertainty_method,
          "confidence_level" => confidence_level,
          "interval" => interval && {
            "lower" => interval[0].round(4),
            "upper" => interval[1].round(4)
          }
        },
        "sample_size" => {
          "valid_trials" => valid_trials,
          "min_effective_trials_unattended" => min_effective_trials_unattended
        },
        "separate_coverage_from_reliability" => separate_coverage_from_reliability?
      }
    end
  end
end
