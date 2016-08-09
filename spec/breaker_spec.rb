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

    context "breaker has an error being handled first" do
      let(:breaker) do
        CB2::Breaker.new(service: "aws",
          duration: 60,
          threshold: 5,
          reenable_after: 600,
          redis: MockRedis.new,
          handle: { RuntimeError => Proc.new { |e|  e.message == 'foo' }})
      end

      it "does not count a class whose handle function returns false" do
        6.times {
          begin
            breaker.run { raise 'sample-runtime-error' }
          rescue
          end
        }
        assert_equal 42, breaker.run { 42 }
      end

      it "counts a class whose handle function returns true" do
        6.times {
          begin
            breaker.run { raise 'foo' }
          rescue
          end
        }
        assert_raises(CB2::BreakerOpen) do breaker.run { 42 } end
      end

      it "counts a class that does not have a handle function defined" do
        6.times {
          begin
            breaker.run { 1 / 0 }
          rescue
          end
        }
        assert_raises(CB2::BreakerOpen) do breaker.run { 42 } end
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
