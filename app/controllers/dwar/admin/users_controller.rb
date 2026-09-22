# frozen_string_literal: true

module Dwar
  module Admin
    class UsersController < BaseController
      # Last-resort cap on serialized picker results. Hosts should scope and
      # cap inside +user_finder+ itself (e.g. a LIMIT query) so a huge table
      # is never loaded per keystroke; this guard only bounds the JSON body.
      PICKER_RESULT_LIMIT = 50

      def index
        query = params[:q].to_s
        results = Dwar.config.user_finder!.call(query)

        items = []
        Array(results).first(PICKER_RESULT_LIMIT).each do |record|
          item = picker_item(record)
          items << item if item
        end

        render json: items
      rescue Dwar::ConfigurationError
        render json: {error: "user_finder not configured"}, status: :service_unavailable
      rescue => e
        # StandardError only, by design: fatal errors (NoMemoryError,
        # SignalException, SystemExit) still propagate as 500s rather than
        # masking a dying process as an empty picker. Logs carry the error
        # class only, never the query or record data (PII).
        Rails.logger.warn("[Dwar] user_finder failed (#{e.class}); returning empty results")
        render json: []
      end

      private

      # Builds one +{id:, label:}+ hash, or nil when the record is unusable.
      # Every host-data problem is contained per record (warn + skip) so a
      # single raising #id/#to_s never wipes the whole result set.
      def picker_item(record)
        unless record.respond_to?(:id)
          Rails.logger.warn("[Dwar] user_finder returned a record without id (#{record.class}); skipped")
          return nil
        end

        id = record.id
        if id.nil?
          Rails.logger.warn("[Dwar] user_finder returned a record with nil id (#{record.class}); skipped")
          return nil
        end

        {id: id, label: display_label(record)}
      rescue => e
        Rails.logger.warn("[Dwar] user_finder record failed (#{e.class}); skipped")
        nil
      end

      def display_label(record)
        display = Dwar.config.user_display || :to_s
        if display.respond_to?(:call)
          display.call(record).to_s
        elsif display.is_a?(Symbol) || display.is_a?(String)
          record.public_send(display).to_s
        else
          record.to_s
        end
      rescue NameError => e
        # Unknown display method or broken callable reference (NoMethodError
        # is a NameError, so both land here): fall back to to_s. Any other
        # host error (or a raising #to_s itself) propagates to #picker_item,
        # which skips just that record.
        Rails.logger.warn("[Dwar] user_display failed (#{e.class}); falling back to to_s")
        record.to_s
      end
    end
  end
end
