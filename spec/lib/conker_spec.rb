require 'conker'

describe Conker do
  before :each do
    @env_vars = ENV.keys
    @constants = Kernel.constants
  end

  after :each do
    # N.B. this doesn't catch if we *changed* any env vars (rather than adding
    # new ones).
    (ENV.keys - @env_vars).each {|k| ENV.delete k }
    # Same caveat doesn't apply here, because Ruby will whinge if we redefine a
    # constant.
    (Kernel.constants - @constants).each do |k|
      Kernel.send :remove_const, k
    end
  end

  describe 'basic usage' do
    def setup!(env = :development)
      Conker.module_eval do
        setup_environment! env,
                           A_SECRET: api_credential(development: nil),
                           PORT: required_in_production(type: :integer, default: 42)
      end
    end

    it 'exposes declared variables as top-level constants' do
      setup!
      ::A_SECRET.should be_nil
      ::PORT.should == 42
    end

    it 'does not turn random environment variables into constants' do
      ENV['PATH'].should_not be_empty
      setup!
      expect { ::PATH }.to raise_error(NameError, /PATH/)
    end

    it 'lets environment variables override environmental defaults' do
      ENV['A_SECRET'] = 'beefbeefbeefbeef'
      setup!
      ::A_SECRET.should == 'beef' * 4
    end

    it 'throws useful errors if required variables are missing' do
      ENV['A_SECRET'].should be_nil
      ENV['PORT'] = '42'
      expect { setup! :production }.to raise_error(/A_SECRET/)
    end
  end
end
