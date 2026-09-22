# frozen_string_literal: true

module Dwar
  module Admin
    class FlagsController < BaseController
      before_action :set_flag, only: %i[edit update destroy]

      def index
        @flags = Dwar::Flag.includes(:groups).order(:key)
        q = params[:q]
        if q.present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
          # Portable case-insensitive match: LOWER() works on SQLite and
          # Postgres alike, and the explicit ESCAPE makes the
          # sanitize_sql_like backslash escapes effective on SQLite.
          @flags = @flags.where(
            "LOWER(dwar_flags.key) LIKE LOWER(:q) ESCAPE '\\' OR " \
            "LOWER(dwar_flags.description) LIKE LOWER(:q) ESCAPE '\\'",
            q: pattern
          )
        end
        # Load once so the view's any?/each below share one query.
        @flags = @flags.load
      end

      def new
        @flag = Dwar::Flag.new
      end

      def create
        @flag = Dwar::Flag.new(flag_params)
        normalize_percentage!

        if @flag.save
          redirect_to admin_flags_path, notice: "Flag was successfully created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        @flag.assign_attributes(flag_params)
        normalize_percentage!

        if @flag.save
          redirect_to admin_flags_path, notice: "Flag was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @flag.destroy
          redirect_to admin_flags_path, notice: "Flag was successfully destroyed."
        else
          redirect_to admin_flags_path, alert: "Flag could not be destroyed."
        end
      end

      private

      def set_flag
        @flag = Dwar::Flag.find(params[:id])
      end

      def flag_params
        params.require(:flag).permit(:key, :description, :state, :percentage, group_ids: [])
      end

      # Non-percentage states ignore the column at evaluation time, so
      # reset it to the default on write: a stale or out-of-range value
      # submitted via the UI can never persist silently and surface
      # later when the flag is switched to a percentage-style state.
      def normalize_percentage!
        @flag.percentage = 0 unless @flag.percentage? || @flag.groups_and_percentage?
      end
    end
  end
end
