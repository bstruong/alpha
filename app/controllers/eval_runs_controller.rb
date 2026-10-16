# frozen_string_literal: true

# Thin API surface for listing and inspecting past evaluation runs.
class EvalRunsController < ApplicationController
  def index
    runs = EvalRun.order(created_at: :desc).limit(50)
    render json: { eval_runs: runs.as_json(include: :task_results) }
  end

  def show
    run = EvalRun.find_by!(run_id: params[:run_id])
    render json: { eval_run: run.as_json(include: :task_results) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Run not found" }, status: :not_found
  end
end
