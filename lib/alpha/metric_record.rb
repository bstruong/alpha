# frozen_string_literal: true

require "fileutils"
require "json"

module Alpha
  # One task trial's numbers and grading verdict.
  # Writes trial data under results/<run_id>/<task_name>/trial-<trial_num>/result.json.
  class MetricRecord
    def self.results_dir
      File.expand_path("../../results", __dir__)
    end

    def self.write!(run_id, attributes)
      task_name = attributes.fetch(:task_name)
      trial = attributes.fetch(:trial, 1)

      dir = File.join(results_dir, "runs", run_id.to_s, task_name.to_s, "trial-#{trial}")
      FileUtils.mkdir_p(dir)

      dest = File.join(dir, "result.json")
      File.write(dest, JSON.pretty_generate(attributes))
      dest
    end
  end
end
