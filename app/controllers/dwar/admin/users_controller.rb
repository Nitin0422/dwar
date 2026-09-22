# frozen_string_literal: true

module Dwar
  module Admin
    class UsersController < BaseController
      def index
        query = params[:q].to_s
        results = Dwar.config.user_finder!.call(query)

        items = []
        Array(results).each do |record|
          # Records must respond to id; skip malformed records with a
          # warning rather than raising a 500 for a host-data problem.
          unless record.respond_to?(:id)
            Rails.logger.warn("[Dwar] user_finder returned record without id for query=#{query.inspect}: #{record.inspect}")
            next
          end

          items << {id: record.id, label: display_label(record)}
        end

        render json: items
      rescue Dwar::ConfigurationError
        render json: {error: "user_finder not configured"}, status: :service_unavailable
      rescue => e
        Rails.logger.warn("[Dwar] user_finder failed for query=#{query.inspect}: #{e.class}: #{e.message}")
        render json: []
      end

      private

      def display_label(record)
        display = Dwar.config.user_display || :to_s
        if display.respond_to?(:call)
          display.call(record).to_s
        elsif display.is_a?(Symbol) || display.is_a?(String)
          record.public_send(display).to_s
        else
          record.to_s
        end
      rescue
        record.to_s
      end
    end
  end
end
