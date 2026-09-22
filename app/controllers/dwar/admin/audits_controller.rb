# frozen_string_literal: true

module Dwar
  module Admin
    # Read-only audit trail (T13, FR-9). Index only: the newest entries
    # first, capped because pagination is deferred. Inherits BaseController
    # so the authorization hook gates this exactly like every other admin
    # screen (fail closed when unconfigured).
    class AuditsController < BaseController
      AUDIT_LIMIT = 200

      helper_method :actor_label, :summary_text

      def index
        @audits = Dwar::Audit.newest_first.limit(AUDIT_LIMIT).to_a
        @record_labels = record_labels(@audits)
      end

      # Actor display: "User #1", or an em dash when the row has no actor
      # (config.audit_actor was unconfigured when the change was made).
      def actor_label(audit)
        return "—" if audit.actor_type.blank?

        "#{audit.actor_type} ##{audit.actor_id}"
      end

      # One-line human rendering of a change-summary hash: from/to pairs
      # read as "state: disabled → enabled", group diffs as
      # "groups: +beta, -gamma". Unknown shapes degrade to key: value.
      def summary_text(summary)
        return "—" unless summary.is_a?(Hash) && summary.any?

        summary.map { |key, value| "#{key}: #{summary_value(value)}" }.join("; ")
      end

      private

      # Best-effort "what was changed" labels, batched (one query per
      # auditable type, no N+1). Records destroyed since the audit row was
      # written fall back to a "Type #id (removed)" label — never a crash.
      def record_labels(audits)
        labels = {}
        audits.group_by(&:auditable_type).each do |type, rows|
          names = live_names(type, rows.map(&:auditable_id).uniq)
          rows.each do |audit|
            labels[audit.id] = names[audit.auditable_id.to_s] || "#{type} ##{audit.auditable_id} (removed)"
          end
        end
        labels
      end

      def live_names(type, ids)
        case type
        when "Dwar::Flag"
          Dwar::Flag.where(id: ids).pluck(:id, :key).to_h { |id, key| [id.to_s, key] }
        when "Dwar::Group"
          Dwar::Group.where(id: ids).pluck(:id, :name).to_h { |id, name| [id.to_s, name] }
        when "Dwar::GroupMembership"
          membership_labels(ids)
        else
          {}
        end
      rescue
        {}
      end

      def membership_labels(ids)
        Dwar::GroupMembership.where(id: ids).includes(:group).to_h do |membership|
          [membership.id.to_s, "#{membership.actor_type} ##{membership.actor_id} in #{membership.group.name}"]
        end
      rescue
        {}
      end

      def summary_value(value)
        case value
        when Hash
          if value.key?("from") || value.key?("to")
            "#{value["from"]} → #{value["to"]}"
          elsif value.key?("added") || value.key?("removed")
            diff_parts(Array(value["added"]), Array(value["removed"]))
          else
            value.map { |key, nested| "#{key}=#{nested}" }.join(", ")
          end
        when Array
          value.join(", ")
        when nil
          "—"
        else
          value.to_s
        end
      end

      def diff_parts(added, removed)
        parts = []
        parts << "+#{added.join(", ")}" if added.any?
        parts << "-#{removed.join(", ")}" if removed.any?
        parts.join(" ").presence || "no change"
      end
    end
  end
end
