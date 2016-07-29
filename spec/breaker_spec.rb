require "spec_helper"

describe CB2::Breaker do
  let(:breaker) do
    CB2::Breaker.new(
      strategy: :stub,
      allow:    false)
  end

  describe "#run" do
    it "raises when the breaker is open" do
      assert_raises(CB2::BreakerOpen) do
        breaker.run { 1+1 }
      end
    end

    it "returns the original value" do
      breaker.strategy.allow = true
      assert_equal 42, breaker.run { 42 }
    end

    context "breaker has RuntimeErrors ignored" do
      let(:breaker) do
        CB2::Breaker.new(service: "aws",
          duration: 60,
          threshold: 5,
          reenable_after: 600,
          redis: MockRedis.new,
          ignore: [RuntimeError])
      end

      it "ignores the error classes specified by the user" do
        6.times {
          begin
            breaker.run { raise 'sample-runtime-error' }
          rescue
          end
        }
        assert_equal 42, breaker.run { 42 }
      end

      it "processes errors not ignored" do
        5.times {
          begin
            breaker.run { raise StandardError.new('sample-standard-error') }
          rescue
          end
        }

        assert_raises(CB2::BreakerOpen) do
          breaker.run { 2 }
        end
      end
    end


    context "breaker has an error handler function" do
      let(:breaker) do
        CB2::Breaker.new(service: "aws",
          duration: 60,
          threshold: 5,
          reenable_after: 600,
          redis: MockRedis.new,
          ignore: [RuntimeError, TypeError],
          error_handler: Proc.new { |e, &h|
            if (e.is_a?(ZeroDivisionError))
              h.call(e)
            else
              if (e.is_a?(RuntimeError) or e.is_a?(IndexError))
                raise e
              else
                42
              end
            end
          })
      end

      it "raises errors in the handler even if listed in ignore" do
        assert_raises(RuntimeError) { breaker.run { raise "sample-rt-error "} }
      end

      it "does not count errors raised in the handler" do
        6.times{
          begin
            breaker.run { raise 'sample-runtime-error' }
          rescue
          end
        }
        assert_raises(RuntimeError) { breaker.run { raise "sample-rt-error "} }
      end

      it "raises non-ignored errors when the handler calls the post-handler" do
        assert_raises(ZeroDivisionError) { breaker.run { 1 / 0 } }
      end

      it "counts non-ignored errors when the handler calls the post-handler" do
        6.times {
          begin
            breaker.run { 1 / 0 }
          rescue
          end
        }
        assert_raises(CB2::BreakerOpen) { breaker.run { 2 } }
      end

      it "does not count a non-ignored error when the post-handler is not called" do
        6.times {
          begin
            breaker.run { [].fetch(0) }
          rescue
          end
        }
        assert_raises(IndexError) { breaker.run { [].fetch(0) } }
      end

      it "ignores an error when the handler does not raise it nor calls the post-handler" do
        assert_equal 42, breaker.run { [].fetch("4") }
      end
    end
  end

  describe "#open?" do
    it "delegates to the strategy" do
      assert breaker.open?
    end

    it "handles Redis errors, just consider the circuit closed" do
      stub(breaker.strategy).open? { raise Redis::BaseError }
      refute breaker.open?
    end
  end
end
