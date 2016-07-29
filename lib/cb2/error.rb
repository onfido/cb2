module CB2
  DEFAULT_ERROR_HANDLER = Proc.new { |error, &post_handle| post_handle.call(error) }

  class BreakerOpen < StandardError
  end
end
