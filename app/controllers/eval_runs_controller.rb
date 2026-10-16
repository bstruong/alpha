# frozen_string_literal: true

# Thin API surface for listing past runs. The real work is bin/alpha + lib/alpha.
class EvalRunsController < ApplicationController
  def index
    # TODO(you): EvalRun.order(created_at: :desc).limit(...)
    render json: { eval_runs: [], note: "stub — implement index" }
  end

  def show
    # TODO(you): find by run_id, include task_results
    render json: { error: "stub — implement show" }, status: :not_implemented
  end

  def create
    # Optional: enqueue a run via ActiveJob. Prefer bin/alpha for Circuit 1.
    render json: { error: "stub — prefer bin/alpha run" }, status: :not_implemented
  end
end
