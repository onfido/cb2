class CB2::Breaker
  attr_accessor :service, :strategy

  def initialize(options)
    @service  = options[:service] || "default"
    @strategy = initialize_strategy(options)
    @ignore = options[:ignore] || []
    @error_handler = options[:error_handler] || CB2::DEFAULT_ERROR_HANDLER
  end

  def run
    if open?
      raise CB2::BreakerOpen
    end

    begin
      process_count
      ret = yield
      process_success
    rescue => error
      return handle_error(error)
    end

    return ret
  end

  def open?
    strategy.open?
  rescue Redis::BaseError
    false
  end

  def process_count
    strategy.count if strategy.respond_to?(:count)
  rescue Redis::BaseError
  end

  def process_success
    strategy.success if strategy.respond_to?(:success)
  rescue Redis::BaseError
  end

  def process_error
    strategy.error if strategy.respond_to?(:error)
  rescue Redis::BaseError
  end

  def initialize_strategy(options)
    strategy_options = options.dup.merge(service: self.service)

    if options[:strategy].respond_to?(:open?)
      return options[:strategy].new(strategy_options)
    end

    case options[:strategy].to_s
    when "", "percentage"
      CB2::Percentage.new(strategy_options)
    when "rolling_window"
      CB2::RollingWindow.new(strategy_options)
    when "stub"
      CB2::Stub.new(strategy_options)
    end
  end

  def handle_error(error)
    after_handle = -> (e) { process_error if should_process? e; raise e }
    return @error_handler.call(error, &after_handle)
  end

  def should_process?(error)
    return !(@ignore.any? { |klass| error.is_a?(klass) })
  end
end
