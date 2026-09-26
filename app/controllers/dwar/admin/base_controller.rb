# frozen_string_literal: true

module Dwar
  module Admin
    # Base controller for the admin namespace. All admin controllers
    # inherit from this and enforce the authorization hook (FR-10:
    # fail closed — no hook configured means every request is denied).
    class BaseController < ::ActionController::Base
      layout "dwar"
      before_action :authorize_admin!

      private

      # Evaluate the host-configured authorization hook.
      # - No hook (nil) or non-callable -> 403 fail-closed.
      # - Hook returns truthy -> proceed.
      # - Hook returns falsy -> 403 fail-closed.
      # - Hook raises -> propagate as 500 (fail-loud, do not rescue).
      def authorize_admin!
        hook = Dwar.config.authorization

        unless hook.respond_to?(:call)
          render plain: "Dwar admin is disabled: no authorization hook configured", status: :forbidden
          return
        end

        result = hook.call(self)

        unless result
          render plain: "Dwar admin is disabled: authorization hook denied access", status: :forbidden
          return # rubocop:disable Style/RedundantReturn -- necessary in Rails before_action to halt action execution
        end
      end
    end
  end
end
