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
          @flags = @flags.where("dwar_flags.key LIKE :q OR dwar_flags.description LIKE :q", q: pattern)
        end
      end

      def new
        @flag = Dwar::Flag.new
      end

      def create
        @flag = Dwar::Flag.new(flag_params)

        if @flag.save
          redirect_to admin_flags_path, notice: "Flag was successfully created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @flag.update(flag_params)
          redirect_to admin_flags_path, notice: "Flag was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @flag.destroy
        redirect_to admin_flags_path, notice: "Flag was successfully destroyed."
      end

      private

      def set_flag
        @flag = Dwar::Flag.find(params[:id])
      end

      def flag_params
        params.require(:flag).permit(:key, :description, :state, :percentage, group_ids: [])
      end
    end
  end
end
