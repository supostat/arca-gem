# frozen_string_literal: true

module ArcaConfig
  class SidekiqMiddleware
    def call(_worker, _job, _queue, &block)
      ArcaConfig.with_snapshot(&block)
    end
  end
end
