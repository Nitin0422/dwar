# frozen_string_literal: true

require_relative "dwar/version"
require_relative "dwar/engine"
require_relative "dwar/configuration"
require_relative "dwar/bucketing"
require_relative "dwar/evaluator"

module Dwar
  class << self
    # Yields a freshly built Dwar::Configuration for the host application to
    # customize, then makes it the current configuration. Requires a block.
    def configure
      raise ArgumentError, "Dwar.configure requires a block" unless block_given?

      @config = Dwar::Configuration.new.tap { |c| yield c }
    end

    # The current Dwar::Configuration. Before any configure call this is the
    # frozen default instance (Dwar::Configuration.default).
    def config
      @config ||= Dwar::Configuration.default
    end

    # Internal: test/dev support. Drops the memoized configuration so the
    # next config read returns the frozen default again; documented as such
    # rather than as a public API.
    def reset_config
      @config = nil
      config
    end

    # Public evaluation API. Returns +true+ or +false+ for whether the
    # flag identified by +flag_key+ is enabled for +actor+. +actor+ is
    # optional and may be omitted for non-percentage checks.
    #
    # Delegates to Dwar::Evaluator.enabled?; never raises.
    def enabled?(flag_key, actor = nil)
      Dwar::Evaluator.enabled?(flag_key, actor)
    end
  end
end
