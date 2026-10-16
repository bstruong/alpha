# frozen_string_literal: true

module Alpha
  # Aggregates MetricRecords into alpha.report.v1 JSON + Markdown under reports/.
  class Report
    def self.build(_run_id)
      # TODO(you): read results/<run_id>/*, compute pass_at_1, write summary.json + .md
      raise NotImplementedError, "#{name}.#{__method__}"
    end
  end
end
