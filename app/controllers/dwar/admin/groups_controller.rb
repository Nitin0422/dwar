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
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)

        begin
          Dwar::ApplicationRecord.transaction do
            @group.save!
            Dwar::Auditing.record!(
              auditable: @group,
              action: "create",
              change_summary: Dwar::Auditing.group_snapshot(@group),
              actor_type: actor_type,
              actor_id: actor_id
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          # Only the group's own validation failure renders the form; an
          # audit-row failure must propagate (same-transaction rollback,
          # never silently swallowed).
          raise unless e.record.equal?(@group)

          render :new, status: :unprocessable_entity
          return
        end

        redirect_to admin_groups_path, notice: "Group was successfully created."
      end

      def edit
      end

      def update
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)
        @group.assign_attributes(group_params)

        begin
          Dwar::ApplicationRecord.transaction do
            @group.save!
            Dwar::Auditing.record!(
              auditable: @group,
              action: "update",
              change_summary: Dwar::Auditing.group_update_summary(@group),
              actor_type: actor_type,
              actor_id: actor_id
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.equal?(@group)

          render :edit, status: :unprocessable_entity
          return
        end

        redirect_to admin_groups_path, notice: "Group was successfully updated."
      end

      def destroy
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)
        summary = Dwar::Auditing.group_snapshot(@group)

        destroyed = false
        Dwar::ApplicationRecord.transaction do
          destroyed = @group.destroy
          if destroyed
            # One row for the admin action: cascade-deleted memberships and
            # flag-group joins are not audited separately.
            Dwar::Auditing.record!(
              auditable: @group,
              action: "destroy",
              change_summary: summary,
              actor_type: actor_type,
              actor_id: actor_id
            )
          else
            # A false destroy changed nothing; roll back (a no-op) without
            # raising so the alert path below still renders.
            raise ActiveRecord::Rollback
          end
        end

        if destroyed
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
