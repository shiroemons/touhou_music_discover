# frozen_string_literal: true

require 'redis'

Redis.current = Redis.new(url: ENV['REDIS_URL'])
