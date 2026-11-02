# frozen_string_literal: true

module Dwar
  module Admin
    class FlagsController < BaseController
      FLAG_LIMIT = 200
      GROUP_OPTIONS_LIMIT = 200

      before_action :set_flag, only: %i[edit update destroy]

      helper_method :group_options

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
        # Cap the list (pagination deferred). Search runs first, so a query
        # still reaches flags beyond the first FLAG_LIMIT rows.
        # Load once so the view's any?/each below share one query.
        @flags = @flags.limit(FLAG_LIMIT).load
      end

      def new
        @flag = Dwar::Flag.new
      end

      def create
        @flag = Dwar::Flag.new(flag_params)
        normalize_percentage!
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)

        begin
          Dwar::ApplicationRecord.transaction do
            @flag.save!
            Dwar::Auditing.record!(
              auditable: @flag,
              action: "create",
              change_summary: Dwar::Auditing.flag_snapshot(@flag),
              actor_type: actor_type,
              actor_id: actor_id
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          # Only the flag's own validation failure renders the form; an
          # audit-row failure must propagate (same-transaction rollback,
          # never silently swallowed).
          raise unless e.record.equal?(@flag)

          render :new, status: :unprocessable_entity
          return
        end

        redirect_to admin_flags_path, notice: "Flag was successfully created."
      end

      def edit
      end

      def update
        old_group_ids = @flag.group_ids
        @flag.assign_attributes(flag_params)
        normalize_percentage!
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)

        begin
          Dwar::ApplicationRecord.transaction do
            @flag.save!
            Dwar::Auditing.record!(
              auditable: @flag,
              action: "update",
              change_summary: Dwar::Auditing.flag_update_summary(@flag, old_group_ids),
              actor_type: actor_type,
              actor_id: actor_id
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.equal?(@flag)

          render :edit, status: :unprocessable_entity
          return
        end

        redirect_to admin_flags_path, notice: "Flag was successfully updated."
      end

      def destroy
        actor_type, actor_id = Dwar::Auditing.resolve_actor(self)
        # Snapshot before the destroy: afterwards the flag_group joins are
        # cascade-deleted and the targeting names would be unrecoverable.
        summary = Dwar::Auditing.flag_snapshot(@flag)

        destroyed = false
        Dwar::ApplicationRecord.transaction do
          destroyed = @flag.destroy
          if destroyed
            Dwar::Auditing.record!(
              auditable: @flag,
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
          redirect_to admin_flags_path, notice: "Flag was successfully destroyed."
        else
          redirect_to admin_flags_path, alert: "Flag could not be destroyed."
        end
      end

      # Options for the flag form's group picker. The list is capped like the
      # index screens, but any group the flag already targets is unioned in
      # and sorted by name so editing an old flag never silently drops its
      # targeting when the host has more groups than the cap.
      def group_options
        @group_options ||= begin
          groups = Dwar::Group.order(:name).limit(GROUP_OPTIONS_LIMIT).to_a
          selected_ids = Array(@flag&.group_ids)
          if selected_ids.any?
            groups += Dwar::Group.where(id: selected_ids).order(:name).to_a
          end
          groups.uniq(&:id).sort_by(&:name)
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
