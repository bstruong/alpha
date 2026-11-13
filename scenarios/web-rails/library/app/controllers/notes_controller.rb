# frozen_string_literal: true

class NotesController < ApplicationController
  def index
    @notes = Note.search(params[:q]).with_tag(params[:tag]).order(:id)
    @receipt_amount = params.fetch(:amount, "1.045")
    @receipt_cents = MoneyCents.round_dollars(@receipt_amount)
  end

  def create
    @note = Note.new(note_params)
    if @note.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to notes_path }
      end
    else
      @notes = Note.order(:id)
      @receipt_amount = params.fetch(:amount, "1.045")
      @receipt_cents = MoneyCents.round_dollars(@receipt_amount)
      render :index, status: :unprocessable_entity
    end
  end

  private
    def note_params
      params.require(:note).permit(:title, :tag)
    end
end
