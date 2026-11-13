# frozen_string_literal: true

class ToolsController < ApplicationController
  def summarize
    payload = params.require(:payload)
    @rows = JsonPipeline.summarize(payload)
    render :summarize
  end

  def parse_config
    @config = LineParser.parse(params.require(:text))
    render :parse_config
  end
end
