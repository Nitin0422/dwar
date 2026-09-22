# frozen_string_literal: true

module Dwar
  # In-process, read-through cache for flag evaluation results.
  #
  # Every +Dwar.enabled?+ call with caching enabled (the default,
  # +Dwar.config.cache+) is served through +Cache.fetch+, keyed by the tuple
  # [flag key, actor type, actor id, global generation, flag version]. Writes
  # bump a global generation counter (invalidating every entry) plus the
  # versions of the flags they touch, so the next evaluation after any
  # committed write recomputes instead of serving stale data.
  #
  # Invalidation is coarse and correct by design: any write evicts every
  # cached entry process-wide (entries are cleared and the generation is
  # bumped under the same lock); per-flag versions add granularity for future
  # selective invalidation. Multi-process caching is out of scope by design
  # (each process holds its own copy).
  #
  # Caveat: invalidation fires from ActiveRecord after_commit hooks, so writes
  # that bypass callbacks (update_column, update_all, delete_all, raw SQL)
  # leave stale entries behind until the next invalidating write.
  #
  # All state is guarded by a single Mutex, and the lock is never held while
  # the fetch block runs (the block hits the database), so concurrent readers
  # cannot deadlock. A computation that races with an invalidation is
  # discarded instead of stored.
  #
  # The counters, clear and reset! below are internal test instrumentation,
  # not public API (same standing as Dwar.reset_config). reset! replaces the
  # lock object itself and is therefore not thread-safe: call it only when no
  # other thread is evaluating.
  module Cache
    # Sentinel distinguishing a cached +false+ from a cache miss.
    CACHE_MISS = Object.new
    private_constant :CACHE_MISS

    class << self
      # Read-through fetch: returns the cached boolean for +flag_key+ and
      # +actor+, or yields to compute it, stores the result and returns it.
      # The key is normalized defensively so the evaluator's never-raise
      # contract holds with caching on.
      def fetch(flag_key, actor = nil)
        key = flag_key.to_s
        actor_type, actor_id = normalize_actor(actor)
        generation, version = snapshot(key)
        cache_key = [key, actor_type, actor_id, generation, version]

        cached = mutex.synchronize do
          if @store.key?(cache_key)
            @hits += 1
            @store[cache_key]
          else
            CACHE_MISS
          end
        end
        return cached unless cached.equal?(CACHE_MISS)

        result = yield
        mutex.synchronize do
          @misses += 1
          # A concurrent invalidation moved the versions on while the block
          # ran: discard the stale computation instead of caching it.
          @store[cache_key] = result if @generation == generation && (@versions[key] || 0) == version
        end
        result
      end

      # Bumps the versions of +flag_keys+ and the global generation while
      # evicting every stored entry, so both targeted entries and every other
      # entry invalidate and stale generations never accumulate in the store.
      # Always bumps the generation, even for an empty key list, so callers
      # that could not resolve keys (e.g. after a cascade destroy) still
      # invalidate.
      def bump_flags(flag_keys)
        keys = Array(flag_keys).compact.map(&:to_s)
        mutex.synchronize do
          keys.each { |k| @versions[k] = (@versions[k] || 0) + 1 }
          @generation += 1
          # Inline the eviction (rather than calling clear) because Mutex is
          # not reentrant.
          @store.clear
        end
      end

      # Best-effort variant resolving flag keys from ids first; falls back to
      # a global-only bump when the flags are already gone. Never raises, so
      # after_commit hooks cannot break the write that triggered them.
      def bump_flags_by_id(flag_ids)
        bump_flags(resolve_flag_keys(flag_ids))
      end

      # Best-effort variant resolving the keys of flags targeting the given
      # groups; same never-raise, global-always semantics as bump_flags_by_id.
      def bump_flags_for_groups(group_ids)
        bump_flags(resolve_group_flag_keys(group_ids))
      end

      # Internal: number of evaluations served from the cache.
      def hits
        mutex.synchronize { @hits }
      end

      # Internal: number of evaluations computed (and stored when still
      # fresh at store time).
      def misses
        mutex.synchronize { @misses }
      end

      # Internal: current global generation; every committed write bumps it.
      def generation
        mutex.synchronize { @generation }
      end

      # Internal, test-only: drops cached entries without touching versions,
      # generation or counters.
      def clear
        mutex.synchronize { @store.clear }
      end

      # Internal, test-only: full reset for test isolation — entries,
      # versions, generation and counters. Not thread-safe (replaces the
      # lock); call only when no other thread is evaluating.
      def reset!
        @mutex = Mutex.new
        @store = {}
        @versions = {}
        @generation = 0
        @hits = 0
        @misses = 0
        true
      end

      private

      attr_reader :mutex

      # Snapshots the versions a fetch is keyed on. A single lock acquisition
      # keeps generation and flag version consistent with each other.
      def snapshot(key)
        mutex.synchronize { [@generation, @versions[key] || 0] }
      end

      def normalize_actor(actor)
        return ["", ""] if actor.nil?

        [actor_type_of(actor), actor_id_of(actor)]
      end

      def actor_type_of(actor)
        actor.class.to_s
      rescue
        ""
      end

      def actor_id_of(actor)
        id = actor.id
        (id.nil? || id.to_s.empty?) ? "" : id.to_s
      rescue
        ""
      end

      def resolve_flag_keys(flag_ids)
        ids = Array(flag_ids).compact.uniq
        return [] if ids.empty?

        Dwar::Flag.where(id: ids).pluck(:key)
      rescue
        []
      end

      def resolve_group_flag_keys(group_ids)
        ids = Array(group_ids).compact.uniq
        return [] if ids.empty?

        Dwar::Flag.joins(:flag_groups).where(flag_groups: {group_id: ids}).distinct.pluck(:key)
      rescue
        []
      end
    end

    reset!
  end
end
