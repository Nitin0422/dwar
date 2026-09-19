# frozen_string_literal: true

require "rails/engine"

module Dwar
  class Engine < ::Rails::Engine
    isolate_namespace Dwar
  end
end
