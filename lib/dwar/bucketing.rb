# frozen_string_literal: true

require "digest"

module Dwar
  # Stable, deterministic percentage bucketing for flag rollouts.
  #
  # Given a flag key, an actor class and an actor id, +#bucket+ returns an
  # integer in 0..99 (inclusive). The same inputs always produce the same
  # bucket — on repeated calls and across Ruby processes/versions — because
  # the bucket derives from a SHA-256 digest of a canonical string tuple,
  # NOT from +Object#hash+/+String#hash+ (which is salted per process and
  # not stable across Ruby versions).
  #
  # == Scheme (versioned — the stability promise)
  #
  #   tuple  = "dwar-v1|<flag_key>|<actor_class>|<actor_id>"
  #   bucket = Digest::SHA256.digest(tuple)[0, 4].unpack1("N") % 100
  #
  # +SCHEME_PREFIX+ ("dwar-v1") marks the scheme version. Any future change
  # to the tuple shape or digest scheme MUST bump it and regenerate the
  # pinned values in test/bucketing_test.rb.
  #
  # Notes on the scheme:
  # - SHA-256 here provides distribution stability, not cryptography.
  # - The mod-100 bias from 2**32 % 100 is ~2.3e-8 relative — acceptable.
  # - The "|" separator is collision-safe only because Dwar flag keys are
  #   validated against Dwar::Flag::KEY_FORMAT (=~ /\A[a-z0-9_\/.-]+\z/),
  #   which forbids "|".
  #
  # == Normalization
  #
  # Different input shapes that denote the same flag/actor map to the same
  # tuple:
  # - +flag_key+: String or Symbol; both normalize via +to_s+.
  # - +actor_class+: any object; normalized via +to_s+, so +User+ and
  #   +"User"+ agree.
  # - +actor_id+: integer or string; normalized via +to_s+, so +42+ and
  #   +"42"+ agree. +nil+ and +""+ are rejected.
  #
  # Actor ids are matched verbatim against persisted ids: there is NO
  # stripping and NO zero-padding normalization, so "42" != "042" and
  # " 42" stays " 42". This is deliberate — a roll-out assignment must be
  # stable for the exact id the host application stores.
  module Bucketing
    BUCKET_COUNT = 100
    SCHEME_PREFIX = "dwar-v1"

    class << self
      # Returns the deterministic rollout bucket (0..99) for a flag and
      # actor. See the module comment for the scheme and normalization rules.
      def bucket(flag_key, actor_class, actor_id)
        key = flag_key.to_s if flag_key.is_a?(String) || flag_key.is_a?(Symbol)
        if key.nil?
          raise ArgumentError,
            "Dwar::Bucketing.bucket flag_key must be a String or Symbol " \
            "(got #{flag_key.class}); use a flag's persisted key, " \
            "e.g. :rollout or \"rollout\""
        end
        if key.empty?
          raise ArgumentError,
            "Dwar::Bucketing.bucket flag_key may not be empty; use a flag's " \
            "persisted key, e.g. :rollout or \"rollout\""
        end

        klass = actor_class.to_s
        if klass.empty?
          raise ArgumentError,
            "Dwar::Bucketing.bucket actor_class may not be empty; pass the " \
            "actor's class object or name, e.g. User or \"User\""
        end

        if actor_id.nil?
          raise ArgumentError,
            "Dwar::Bucketing.bucket actor_id must not be nil; a stable id " \
            "(integer or string, e.g. 42 or \"42\") is required so an actor " \
            "always lands in the same bucket"
        end
        id = actor_id.to_s
        if id.empty?
          raise ArgumentError,
            "Dwar::Bucketing.bucket actor_id may not be empty; a stable id " \
            "(integer or string, e.g. 42 or \"42\") is required so an actor " \
            "always lands in the same bucket"
        end

        digest_value(scheme_tuple(key, klass, id))
      end

      private

      def scheme_tuple(flag_key, actor_class, actor_id)
        [SCHEME_PREFIX, flag_key, actor_class, actor_id].join("|")
      end

      def digest_value(string)
        Digest::SHA256.digest(string)[0, 4].unpack1("N") % BUCKET_COUNT
      end
    end
  end
end
