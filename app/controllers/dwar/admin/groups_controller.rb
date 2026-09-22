# frozen_string_literal: true

module Dwar
  module Admin
    class GroupsController < BaseController
      before_action :set_group, only: %i[edit update destroy]

      def index
        @groups = Dwar::Group.order(:name).to_a
        counts = Dwar::GroupMembership.where(group_id: @groups.map(&:id)).group(:group_id).count
        @member_counts = counts
      end

      def new
        @group = Dwar::Group.new
      end

      def create
        @group = Dwar::Group.new(group_params)

        if @group.save
          redirect_to admin_groups_path, notice: "Group was successfully created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @group.update(group_params)
          redirect_to admin_groups_path, notice: "Group was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @group.destroy
          redirect_to admin_groups_path, notice: "Group was successfully destroyed."
        else
          redirect_to admin_groups_path, alert: "Group could not be deleted."
        end
      end

      private

      def set_group
        @group = Dwar::Group.find(params[:id])
      end

      def group_params
        params.require(:group).permit(:name, :description)
      end
    end
  end
end
