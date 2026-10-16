# frozen_string_literal: true

module Alpha
  # One task trial's numbers. Prefer writing JSON under results/<run_id>/ (gitignored).
  # Optional: mirror into ActiveRecord::TaskResult for browsing — your choice later.
  class MetricRecord
    def self.write!(_run_id, _attributes)
      # TODO(you): append/write results/<run_id>/tasks/<name>.json
      raise NotImplementedError, "#{name}.#{__method__}"
    end
  end
end
