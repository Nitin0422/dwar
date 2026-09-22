# frozen_string_literal: true

module Dwar
  module Admin
    # Per-group membership management (T12, FR-6/FR-7).
    #
    # Thin screen on existing primitives: memberships are always scoped to
    # their group through the nested /admin/groups/:group_id/memberships
    # routes, and evaluation/cache consistency comes from the existing
    # GroupMembership after_commit hooks (T07) — no cache code here.
    #
    # The add form trusts the picker selection (id + type) after the
    # actor_type allowlist below; it is NOT re-validated against user_finder.
    class MembershipsController < BaseController
      before_action :set_group
      before_action :set_membership, only: [:destroy]

      def index
        load_members
        @membership = @group.group_memberships.new
      end

      def create
        actor_type = resolve_actor_type(membership_params[:actor_type])

        unless actor_type
          load_members
          @membership = @group.group_memberships.new
          @membership.errors.add(:actor_type, "is invalid")
          render :index, status: :unprocessable_entity
          return
        end

        @membership = @group.group_memberships.new(
          actor_type: actor_type,
          actor_id: membership_params[:actor_id]
        )
        audit_actor_type, audit_actor_id = Dwar::Auditing.resolve_actor(self)

        begin
          Dwar::ApplicationRecord.transaction do
            @membership.save!
            Dwar::Auditing.record!(
              auditable: @membership,
              action: "create",
              change_summary: Dwar::Auditing.membership_summary(@group, @membership),
              actor_type: audit_actor_type,
              actor_id: audit_actor_id
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          # Only the membership's own validation failure re-renders the
          # list; an audit-row failure must propagate (same-transaction
          # rollback, never silently swallowed).
          raise unless e.record.equal?(@membership)

          load_members
          render :index, status: :unprocessable_entity
          return
        end

        redirect_to admin_group_memberships_path(@group), notice: "Member was successfully added."
      end

      def destroy
        audit_actor_type, audit_actor_id = Dwar::Auditing.resolve_actor(self)
        summary = Dwar::Auditing.membership_summary(@group, @membership)

        destroyed = false
        Dwar::ApplicationRecord.transaction do
          destroyed = @membership.destroy
          if destroyed
            Dwar::Auditing.record!(
              auditable: @membership,
              action: "destroy",
              change_summary: summary,
              actor_type: audit_actor_type,
              actor_id: audit_actor_id
            )
          else
            # A false destroy changed nothing; roll back (a no-op) without
            # raising so the alert path below still renders.
            raise ActiveRecord::Rollback
          end
        end

        if destroyed
          redirect_to admin_group_memberships_path(@group), notice: "Member was successfully removed."
        else
          redirect_to admin_group_memberships_path(@group), alert: "Member could not be removed."
        end
      end

      private

      def set_group
        @group = Dwar::Group.find(params[:group_id])
      end

      def set_membership
        @membership = @group.group_memberships.find(params[:id])
      end

      # The picker posts membership[actor_id] + membership[actor_type]. A
      # missing or malformed membership param normalizes to {} so the action
      # 422s on validation instead of 400ing on ParameterMissing.
      def membership_params
        raw = params[:membership]
        raw = ActionController::Parameters.new unless raw.is_a?(ActionController::Parameters)
        raw.permit(:actor_id, :actor_type)
      end

      # Allowlist guard for the posted actor_type: blank defaults to "User";
      # anything else must safe_constantize to a concrete, non-internal
      # ActiveRecord class. Dwar::* engine models (Flag, Group, ...) and
      # ActiveRecord::* internals (SchemaMigration, ...) are never valid
      # membership actors — the picker only ever offers host user records
      # (FR-6/FR-7) — so they 422 like any other unknown type. The string
      # is never constantized blindly and no record is ever instantiated
      # from it.
      def resolve_actor_type(raw)
        value = raw.to_s.strip
        value = "User" if value.empty?
        klass = value.safe_constantize
        return nil unless klass.is_a?(Class)
        return nil unless klass <= ActiveRecord::Base
        return nil if klass.abstract_class?
        name = klass.name
        return nil if name.nil?
        return nil if name.start_with?("Dwar::", "ActiveRecord::")

        name
      rescue
        nil
      end

      def load_members
        @memberships = @group.group_memberships.order(:actor_type, :actor_id).to_a
        @member_labels = member_labels(@memberships)
      end

      # Batched label lookup: one query per actor type (no N+1), then
      # defensive per-record labels that can never 500 (see display_label).
      def member_labels(memberships)
        labels = {}
        memberships.group_by(&:actor_type).each do |type, members|
          records = records_by_id(type, members.map(&:actor_id).uniq)
          members.each do |membership|
            record = records[membership.actor_id.to_s]
            labels[membership.id] = record ? display_label(record, membership) : fallback_label(membership)
          end
        end
        labels
      end

      def records_by_id(type, ids)
        klass = type.safe_constantize
        unless klass.is_a?(Class) && klass <= ActiveRecord::Base
          Rails.logger.warn("[Dwar] membership lookup skipped for unresolvable actor type; using fallback labels")
          return {}
        end

        # Ids come off the string actor_id column, so bind them as strings:
        # explicit to_s keeps the lookup correct regardless of adapter
        # coercion rules (mirrors Evaluator/Cache normalization).
        klass.where(id: ids.map(&:to_s)).index_by { |record| record.id.to_s }
      rescue => e
        # Log class only, never ids or record data (PII).
        Rails.logger.warn("[Dwar] membership lookup failed (#{e.class}); using fallback labels")
        {}
      end

      # Defensive label resolution via Dwar.config.user_display, mirroring
      # UsersController: Symbol/String -> public_send, callable -> call,
      # anything else -> to_s. Any host error blanks only this row via
      # safe_to_s — never the page. (UsersController differentiates
      # NameError from other errors because its picker_item skips bad
      # records; here every failure mode falls back the same way, so a
      # single rescue branch covers both.)
      def display_label(record, membership)
        display = Dwar.config.user_display || :to_s
        if display.respond_to?(:call)
          display.call(record).to_s
        elsif display.is_a?(Symbol) || display.is_a?(String)
          record.public_send(display).to_s
        else
          record.to_s
        end
      rescue => e
        Rails.logger.warn("[Dwar] user_display failed (#{e.class}); falling back to to_s")
        safe_to_s(record, membership)
      end

      def safe_to_s(record, membership)
        record.to_s
      rescue => e
        Rails.logger.warn("[Dwar] membership label failed (#{e.class}); using fallback label")
        fallback_label(membership)
      end

      # Members whose actor record no longer resolves (deleted host record
      # or unresolvable type) render a plain fallback — never a crash.
      def fallback_label(membership)
        "#{membership.actor_type} ##{membership.actor_id} (removed)"
      end
    end
  end
end
