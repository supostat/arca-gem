# frozen_string_literal: true

module ArcaConfig
  class RackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      ArcaConfig.with_snapshot { @app.call(env) }
    end
  end
end
