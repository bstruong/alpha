# frozen_string_literal: true

module Alpha
  # Ephemeral worktree or directory copy for one task trial.
  class Sandbox
    attr_reader :path

    def self.provision(_task)
      # TODO(you): git worktree add --detach (preferred) or copy scenario library
      raise NotImplementedError, "#{name}.#{__method__}"
    end

    def initialize(path:)
      @path = path
    end

    def teardown!
      # TODO(you): git worktree remove --force or FileUtils.rm_rf
      raise NotImplementedError, "#{self.class}##{__method__}"
    end
  end
end
