# frozen_string_literal: true

module Dwar
  # Public evaluation API implementing FR-3 resolution.
  #
  # Returns +true+ or +false+ for whether a flag is enabled for an actor,
  # never raising regardless of inputs. Delegates all percentage math to
  # Dwar::Bucketing; no hash or bucket logic is duplicated here.
  module Evaluator
    class << self
      # Returns +true+ or +false+ for whether the flag identified by
      # +flag_key+ is enabled for +actor+. +actor+ is optional and may
      # be omitted for non-percentage checks.
      #
      # Resolution order:
      # 1. Unknown flag key -> +false+ (never raises).
      # 2. Flag disabled -> +false+.
      # 3. Flag fully enabled -> +true+.
      # 4. Percentage-only -> +true+ iff actor supplied with a stable id
      #    AND +Bucketing.bucket(actor) < percentage+; no actor -> +false+.
      # 5. Group-targeted -> actor must belong to a targeted group AND,
      #    when a percentage is set, +Bucketing.bucket(actor) < percentage+.
      def enabled?(flag_key, actor = nil)
        flag = Dwar::Flag.find_by(key: flag_key.to_s)
        return false unless flag

        if flag.disabled?
          false
        elsif flag.enabled?
          true
        elsif flag.percentage?
          return false unless actor
          bucket = safe_bucket?(flag, actor)
          bucket && bucket < flag.percentage
        elsif flag.groups?
          return false unless actor
          belongs_to_targeted_group?(actor, flag)
        elsif flag.groups_and_percentage?
          return false unless actor
          belongs_to_targeted_group?(actor, flag) &&
            (bucket = safe_bucket?(flag, actor)) && bucket < flag.percentage
        else
          false
        end
      end

      private

      # Returns the bucket for a valid actor, or +nil+ if the actor's id
      # is nil/empty so that Bucketing is never called with invalid args.
      def safe_bucket?(flag, actor)
        actor_id = actor.id
        return nil if actor_id.nil? || actor_id.to_s.empty?

        Dwar::Bucketing.bucket(flag.key, actor.class, actor_id)
      rescue ArgumentError
        nil
      end

      # Returns +true+ if +actor+ belongs to any targeted group of the flag.
      def belongs_to_targeted_group?(actor, flag)
        actor_type = actor.class.to_s
        actor_id = actor.id
        return false if actor_id.nil? || actor_id.to_s.empty?

        Dwar::GroupMembership.where(actor_type: actor_type, actor_id: actor_id)
          .where(group_id: flag.group_ids)
          .exists?
      end
    end
  end
end
