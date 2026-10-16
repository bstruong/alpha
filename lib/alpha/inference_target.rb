# frozen_string_literal: true

module Alpha
  # Points at the AM5 homelab OpenAI-compatible endpoint (never the Haswell desk).
  # See docs/infrastructure-topology.md and engine/models.ini.
  class InferenceTarget
    attr_reader :base_url, :model_id, :engine_preset

    def self.from_engine(_preset_name)
      # TODO(you): parse engine/models.ini + workstation.env (or env overrides)
      raise NotImplementedError, "#{name}.#{__method__}"
    end

    def initialize(base_url:, model_id:, engine_preset:)
      @base_url = base_url
      @model_id = model_id
      @engine_preset = engine_preset
    end

    def healthy?
      # TODO(you): GET /v1/models (or /health) and confirm model_id is present
      raise NotImplementedError, "#{self.class}##{__method__}"
    end
  end
end
