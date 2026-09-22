# frozen_string_literal: true

module Dwar
  # Explicit, same-transaction audit recording for the admin UI (T13).
  #
  # Controllers resolve the actor once per mutating request via
  # {.resolve_actor} and then wrap the model write AND the {.record!} call
  # in a single +Dwar::ApplicationRecord.transaction+, so an audit failure
  # rolls the write back and surfaces instead of being silently swallowed.
  # Recording deliberately lives outside model callbacks (and outside
  # after_commit): the T07 cache hooks stay untouched, and direct model
  # writes (console, seeds) simply leave no trail.
  #
  # Join-table churn is not audited directly: flag create/update summaries
  # already capture targeting as a group-name diff, and a flag/group
  # destroy writes exactly one row for the admin action even though its
  # joins cascade. Summaries are curated diffs with denormalized labels
  # (group names, not full records) to bound size and PII.
  module Auditing
    class << self
      # Resolve the audit actor for this request. Evaluates the optional
      # +config.audit_actor+ callable with the controller — the same
      # controller-context contract as the authorization hook — and
      # normalizes the result to a [type, id] string pair mirroring
      # Cache.normalize_actor (nil-safe: extraction failures become nil).
      #
      # - No hook (nil) or a non-callable -> [nil, nil] (null actor).
      # - Hook returns nil/false -> [nil, nil].
      # - Hook raises -> propagates (fail-loud, consistent with
      #   authorization); the write never commits unattributed-by-accident.
      def resolve_actor(controller)
        hook = Dwar.config.audit_actor
        return [nil, nil] unless hook.respond_to?(:call)

        actor = hook.call(controller)
        return [nil, nil] unless actor

        [actor_type_of(actor), actor_id_of(actor)]
      end

      # Write one audit row. Raises on validation failure so callers inside
      # a transaction roll the whole write back (never swallowed).
      def record!(auditable:, action:, change_summary:, actor_type: nil, actor_id: nil)
        Dwar::Audit.create!(
          auditable_type: auditable.class.name,
          auditable_id: auditable.id.to_s,
          action: action,
          change_summary: change_summary || {},
          actor_type: actor_type,
          actor_id: actor_id&.to_s
        )
      end

      # Point-in-time snapshot of a flag for create/destroy summaries.
      # Callers capturing a destroy summary must call this BEFORE the
      # destroy runs (afterwards the joins are cascade-deleted).
      def flag_snapshot(flag)
        {
          "key" => flag.key,
          "description" => flag.description,
          "state" => flag.state,
          "percentage" => flag.percentage,
          "groups" => flag.groups.map(&:name)
        }
      end

      # Curated diff for a flag update. Reads +flag.previous_changes+ (so
      # call after a successful save, inside the same transaction) plus an
      # explicit old-vs-new group diff; unchanged attributes are omitted.
      def flag_update_summary(flag, old_group_ids)
        summary = {}
        flag.previous_changes
          .slice("key", "description", "state", "percentage")
          .each do |attr, (from, to)|
            summary[attr] = {"from" => from, "to" => to}
          end

        old_ids = Array(old_group_ids).map(&:to_s)
        new_ids = flag.group_ids.map(&:to_s)
        if old_ids.sort != new_ids.sort
          summary["groups"] = {
            "added" => group_names(new_ids - old_ids),
            "removed" => group_names(old_ids - new_ids)
          }
        end
        summary
      end

      # Point-in-time snapshot of a group for create/destroy summaries.
      def group_snapshot(group)
        {"name" => group.name, "description" => group.description}
      end

      # Curated diff for a group update (call after a successful save).
      def group_update_summary(group)
        summary = {}
        group.previous_changes
          .slice("name", "description")
          .each do |attr, (from, to)|
            summary[attr] = {"from" => from, "to" => to}
          end
        summary
      end

      # Membership add/remove summary. Group identity comes from the
      # controller's loaded @group (safe even after the row is gone);
      # member identity is the polymorphic actor reference itself.
      def membership_summary(group, membership)
        {
          "group_id" => group.id,
          "group" => group.name,
          "actor_type" => membership.actor_type,
          "actor_id" => membership.actor_id.to_s
        }
      end

      private

      def actor_type_of(actor)
        actor.class.to_s
      rescue
        nil
      end

      def actor_id_of(actor)
        id = actor.id
        (id.nil? || id.to_s.empty?) ? nil : id.to_s
      rescue
        nil
      end

      # Best-effort id -> name resolution for group diffs; ids whose group
      # no longer resolves fall back to a "#id" label instead of 500ing.
      def group_names(ids)
        ids = Array(ids).map(&:to_s).uniq
        return [] if ids.empty?

        names = Dwar::Group.where(id: ids).pluck(:id, :name).to_h
        ids.map { |id| names[id.to_i] || names[id] || "##{id}" }
      rescue
        ids.map { |id| "##{id}" }
      end
    end
  end
end
