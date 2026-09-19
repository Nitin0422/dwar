# frozen_string_literal: true

module Dwar
  # Raised when Dwar is used in a way that requires configuration the host
  # application never provided. See Dwar::Configuration#user_finder!.
  class ConfigurationError < StandardError; end

  # Host-application configuration surface for the Dwar engine.
  #
  # Applications configure Dwar once in an initializer:
  #
  #   Dwar.configure do |c|
  #     c.user_finder   = ->(query) { User.search(query) }
  #     c.user_display  = :display_name
  #     c.admin_path    = "/admin/dwar"
  #     c.authorization = ->(controller) { controller.current_user.admin? }
  #     c.cache         = true
  #     c.audit_actor   = ->(controller) { controller.current_user }
  #   end
  #
  # Every Dwar.configure call builds a fresh instance with the defaults below,
  # so configuration never leaks between apps or between configure blocks.
  class Configuration
    attr_accessor :user_finder, :user_display, :admin_path,
      :authorization, :cache, :audit_actor

    def initialize
      # user_finder: how the user picker looks up records to choose from.
      # Type: callable ->(query) { users }, accepting a query String and
      # returning an enumerable of user records. Default: nil (unset —
      # required only when the picker endpoint is exercised, T11).
      # Example: c.user_finder = ->(query) { User.search(query) }
      @user_finder = nil

      # user_display: method name used to render user picker labels.
      # Type: Symbol method name (T11 interprets symbol-vs-callable later).
      # Default: :to_s. Example: c.user_display = :display_name
      @user_display = :to_s

      # admin_path: path the engine mounts its admin UI at (consumed by T08
      # for the engine mount line). Type: String. Default: "/dwar".
      # Example: c.admin_path = "/admin/dwar"
      @admin_path = "/dwar"

      # authorization: gatekeeper for the admin UI. Type: callable
      # ->(controller) { bool }; nil means every request is denied (FR-10).
      # Stored opaque; evaluated later in the admin controller context (T08).
      # Default: nil. Example: c.authorization = ->(controller) { controller.current_user.admin? }
      @authorization = nil

      # cache: whether flag evaluation results are cached. Type: Boolean
      # toggle for the evaluation cache (T07). Default: true.
      # Example: c.cache = false
      @cache = true

      # audit_actor: how changes attribute audit entries. Type: optional
      # callable ->(controller) { identity } evaluated in admin context (T13).
      # Default: nil. Example: c.audit_actor = ->(controller) { controller.current_user }
      @audit_actor = nil
    end

    # A frozen, default-valued instance used until the host application calls
    # Dwar.configure. Frozen so accidental in-place mutation fails loudly
    # instead of silently altering boot-time defaults.
    def self.default
      new.freeze
    end

    # Returns the configured user finder, raising ConfigurationError when it
    # has not been set. The requirement is deferred to the call site (the
    # picker action, T11) so requiring or booting Dwar never raises; a plain
    # read of +user_finder+ returns +nil+ instead.
    def user_finder!
      return user_finder unless user_finder.nil?

      raise ConfigurationError,
        "Dwar user_finder is not configured. Set it in an initializer: " \
        "Dwar.configure { |c| c.user_finder = ->(query) { User.search(query) } } " \
        "before using the user picker."
    end
  end
end
