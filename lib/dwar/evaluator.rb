# frozen_string_literal: true

module Dwar
  # Public evaluation API implementing FR-3 resolution.
  #
  # Returns +true+ or +false+ for whether a flag is enabled for an actor,
  # never raising regardless of inputs. Delegates all percentage math to
  # Dwar::Bucketing; no hash or bucket logic is duplicated here.
  #
  # Results are cached in-process via Dwar::Cache while Dwar.config.cache is
  # truthy (the default). Committed writes invalidate through model
  # after_commit hooks; with caching disabled every call re-evaluates.
  module Evaluator
    class << self
      # Returns +true+ or +false+ for whether the flag identified by
      # +flag_key+ is enabled for +actor+. +actor+ is optional and may
      # be omitted for non-percentage checks.
      #
      # With caching enabled the result is served from Dwar::Cache keyed by
      # [flag key, actor type, actor id, generation, flag version]; with
      # caching disabled the flag is resolved on every call.
      def enabled?(flag_key, actor = nil)
        return evaluate(flag_key, actor) unless Dwar.config.cache

        Dwar::Cache.fetch(flag_key, actor) { evaluate(flag_key, actor) }
      end

      private

      # Core FR-3 resolution (uncached).
      #
      # Resolution order:
      # 1. Unknown flag key -> +false+ (never raises).
      # 2. Flag disabled -> +false+.
      # 3. Flag fully enabled -> +true+.
      # 4. Percentage-only -> +true+ iff actor supplied with a stable id
      #    AND +Bucketing.bucket(actor) < percentage+; no actor -> +false+.
      # 5. Group-targeted -> actor must belong to a targeted group AND,
      #    when a percentage is set, +Bucketing.bucket(actor) < percentage+.
      def evaluate(flag_key, actor)
        flag = Dwar::Flag.find_by(key: flag_key.to_s)
        return false unless flag

        if flag.disabled?
          false
        elsif flag.enabled?
          true
        elsif flag.percentage?
          return false unless actor
          bucket = safe_bucket(flag, actor)
          return false unless bucket
          bucket < flag.percentage
        elsif flag.groups?
          return false unless actor
          belongs_to_targeted_group?(actor, flag)
        elsif flag.groups_and_percentage?
          return false unless actor
          return false unless belongs_to_targeted_group?(actor, flag)
          bucket = safe_bucket(flag, actor)
          return false unless bucket
          bucket < flag.percentage
        else
          false
        end
      end

      # Returns the bucket for a valid actor, or +nil+ if the actor's id
      # is nil/empty so that Bucketing is never called with invalid args.
      # Out-of-contract actors (e.g. objects without an id) also yield +nil+
      # instead of raising, preserving the never-raise contract and matching
      # the cache's defensive key normalization.
      def safe_bucket(flag, actor)
        actor_id = actor.id
        return nil if actor_id.nil? || actor_id.to_s.empty?

        Dwar::Bucketing.bucket(flag.key, actor.class, actor_id)
      rescue
        nil
      end

      # Returns +true+ if +actor+ belongs to any targeted group of the flag.
      # Out-of-contract actors yield +false+ instead of raising, as above.
      #
      # actor_id is bound as an explicit String: the column is varchar since
      # T12, and binding a raw Integer would rely on adapter coercion. On
      # PostgreSQL an integer bind against a varchar column holding
      # non-numeric (UUID) ids forces a column-side cast and can raise;
      # to_s keeps the lookup correct on every adapter.
      def belongs_to_targeted_group?(actor, flag)
        actor_type = actor.class.to_s
        actor_id = actor.id
        return false if actor_id.nil? || actor_id.to_s.empty?

        Dwar::GroupMembership.where(actor_type: actor_type, actor_id: actor_id.to_s)
          .where(group_id: flag.group_ids)
          .exists?
      rescue
        false
      end
    end
  end
end
