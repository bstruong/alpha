# frozen_string_literal: true

module Alpha
  class Configuration
    attr_accessor :root, :default_base_url, :default_model,
                  :node_class, :qualification_schema
    attr_writer :scenarios_dir, :results_dir, :reports_dir,
                :qualifications_dir, :engine_ini_path, :harness_dir, :pi_bin

    def initialize
      reset!
    end

    def reset!
      @root = ENV.fetch("ALPHA_ROOT", Dir.pwd)
      @default_base_url = ENV["OPENAI_API_BASE"] || ENV["OPENAI_BASE_URL"] ||
                          (ENV["LLAMA_SERVER_URL"] && "#{ENV["LLAMA_SERVER_URL"].chomp("/")}/v1") ||
                          "http://127.0.0.1:8080/v1"
      @default_model = ENV.fetch("ALPHA_MODEL", "qwen36-coder-hybrid")
      @node_class = ENV.fetch("ALPHA_NODE_CLASS", "am5-homelab-32g-3060")
      @qualification_schema = ENV.fetch("ALPHA_QUALIFICATION_SCHEMA", "alpha.qualification.v1")
      @scenarios_dir = nil
      @results_dir = nil
      @reports_dir = nil
      @qualifications_dir = nil
      @engine_ini_path = nil
      @harness_dir = nil
    end

    def scenarios_dir
      @scenarios_dir || File.join(root, "scenarios")
    end

    def results_dir
      @results_dir || File.join(root, "results")
    end

    def reports_dir
      @reports_dir || File.join(root, "reports")
    end

    def qualifications_dir
      @qualifications_dir || File.join(root, "qualifications")
    end

    def engine_ini_path
      @engine_ini_path || File.join(root, "engine", "models.ini")
    end

    def harness_dir
      @harness_dir || File.join(root, "harness", "pi")
    end

    def pi_bin
      return @pi_bin if @pi_bin
      return ENV["PI_BIN"] if ENV["PI_BIN"] && !ENV["PI_BIN"].empty?

      system_pi = `which pi 2>/dev/null`.strip
      return system_pi if !system_pi.empty? && File.executable?(system_pi)

      File.join(harness_dir, "node_modules", ".bin", "pi")
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def reset_config!
      @config = Configuration.new
    end
  end
end
