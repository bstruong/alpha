# frozen_string_literal: true

module Alpha
  # Ordered list of tasks + budget + default inference target.
  class Scenario
    attr_reader :id, :tasks, :profile

    def self.load(_id)
      # TODO(you): resolve scenarios/<id>, load tasks in declared order
      raise NotImplementedError, "#{name}.#{__method__}"
    end

    def initialize(id:, tasks:, profile: "shipping")
      @id = id
      @tasks = tasks
      @profile = profile
    end
  end
end
