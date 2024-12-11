# frozen_string_literal: true

require "yabeda"
require "active_support"
require "rails/railtie"
require "yabeda/rails/railtie"
require "yabeda/rails/config"
require "yabeda/rails/event"

module Yabeda
  # Minimal set of Rails-specific metrics for using with Yabeda
  module Rails
    LONG_RUNNING_REQUEST_BUCKETS = [
      0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, # standard
      30, 60, # We timeout requests at 100s. Requests taking more than 60s will end up in the Infinity bucket
    ].freeze

    class << self
      def controller_handlers
        @controller_handlers ||= []
      end

      def on_controller_action(&block)
        controller_handlers << block
      end

      # Declare metrics and install event handlers for collecting themya
      # rubocop: disable Metrics/MethodLength, Metrics/AbcSize
      def install!
        Yabeda.configure do
          config = ::Yabeda::Rails.config

          group :rails

          counter   :requests_total,   comment: "A counter of the total number of HTTP requests rails processed.",
                                       tags: %i[controller action status format method]

          histogram :request_duration, tags: %i[controller action status format method],
                                       unit: :seconds,
                                       buckets: LONG_RUNNING_REQUEST_BUCKETS,
                                       comment: "A histogram of the response latency."

          if config.apdex_target
            gauge :apdex_target, unit: :seconds,
                                 comment: "Tolerable time for Apdex (T value: maximum duration of satisfactory request)"
            collect { rails_apdex_target.set({}, config.apdex_target) }
          end

          ActiveSupport::Notifications.subscribe "process_action.action_controller" do |*args|
            event = Yabeda::Rails::Event.new(*args)

            rails_requests_total.increment(event.labels)
            rails_request_duration.measure(event.labels, event.duration)

            Yabeda::Rails.controller_handlers.each do |handler|
              handler.call(event, event.labels)
            end
          end
        end
      end
      # rubocop: enable Metrics/MethodLength, Metrics/AbcSize

      def config
        @config ||= Config.new
      end
    end
  end
end
