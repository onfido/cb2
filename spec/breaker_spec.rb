require "spec_helper"

describe CB2::Breaker do
  let(:breaker) do
    CB2::Breaker.new(
      strategy: :stub,
      allow:    false)
  end

  before do
    # allow(Redis).to receive(:new).and_return(MockRedis.new)
  end

  after do
    # allow(Redis).to receive(:new).and_call_original
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

    context "breaker has RuntimeErrors whitelisted" do
      let(:breaker) do
        CB2::Breaker.new(service: "aws",
          duration: 60,
          threshold: 5,
          reenable_after: 600,
          redis: MockRedis.new,
          whitelist: [RuntimeError])
      end

      it "ignores whitelisted error classes" do
        6.times {
          begin
            breaker.run { raise 'sample-runtime-error' }
          rescue
          end
        }
        assert_equal 42, breaker.run { 42 }
      end

      it "does not ignore errors not whitelisted" do
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
