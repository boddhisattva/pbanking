
# frozen_string_literal: true

# Allows using additional matchers for Sidekiq jobs in RSpec tests
# rspec-sidekiq requires sidekiq/testing by default
# Requiring sidekiq/testing will automatically call Sidekiq::Testing.fake!
require "rspec-sidekiq"

# Configure Sidekiq for test environment
RSpec.configure do |config|
  # Set fake mode globally for ALL tests
  # This ensures Sidekiq jobs are queued but never executed
  # The fake option is the default option for sidekiq/testing
  # so we don't need to set it explicitly below
  # config.before(:suite) do
  #   Sidekiq::Testing.fake!
  # end

  # Worker queues are global and will therefore persist between tests.
  # Clear all Sidekiq job queues before each test
  # This prevents job and related state contamination between tests
  # This also helps keep to make sure tests are order independent
  # We don't need to clear the queues explicitly below if we are using rspec-sidekiq
  # as rspec-sidekiq will clear the enqueued jobs automatically
  # as mentioned here: https://github.com/wspurgin/rspec-sidekiq
  # config.before do
  #   Sidekiq::Worker.clear_all
  # end

  # Run Sidekiq jobs inline for tests marked with :sidekiq_inline metadata
  config.around do |example|
    if example.metadata[:sidekiq_inline] == true
      Sidekiq::Testing.inline! { example.run }
    else
      example.run
    end
  end
end
