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
        setup_config! env,
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


  describe 'required variables' do
    def setup!
      env = @env # capture it for block scope
      Conker.module_eval do
        setup_config! env,
          APPNAME: optional(default: 'conker'),
          PORT: required_in_production(type: :integer, default: 3000)
      end
    end

    describe 'in development' do
      before { @env = :development }

      it 'allows optional variables to be missing' do
        ENV['APPNAME'].should be_nil
        ENV['PORT'] = '80'
        expect { setup! }.not_to raise_error
      end

      it 'allows required_in_production variables to be missing' do
        ENV['APPNAME'] = 'widget'
        ENV['PORT'].should be_nil
        expect { setup! }.not_to raise_error
      end
    end

    describe 'in production' do
      before { @env = :production }

      it 'allows optional variables to be missing' do
        ENV['APPNAME'].should be_nil
        ENV['PORT'] = '80'
        expect { setup! }.not_to raise_error
      end

      it 'throws a useful error if required_in_production variables are missing' do
        ENV['APPNAME'] = 'widget'
        ENV['PORT'].should be_nil
        expect { setup! }.to raise_error(/PORT/)
      end
    end
  end


  describe 'defaults' do
    def setup!(env = :development)
      Conker.module_eval do
        setup_config! env, NUM_THREADS: optional(type: :integer, test: 1, default: 2)
      end
    end

    it 'uses the specified value if one is given' do
      ENV['NUM_THREADS'] = '4'
      setup!
      NUM_THREADS.should == 4
    end

    it 'uses the default value if none is specified' do
      ENV['NUM_THREADS'].should be_nil
      setup!
      NUM_THREADS.should == 2
    end

    it 'allows overriding defaults for specific environments' do
      ENV['NUM_THREADS'].should be_nil
      setup! :test
      NUM_THREADS.should == 1
    end
  end


  describe 'typed variables' do
    describe 'boolean' do
      def setup_sprocket_enabled!(value_string)
        ENV['SPROCKET_ENABLED'] = value_string
        Conker.module_eval do
          setup_config! :development, :SPROCKET_ENABLED => optional(type: :boolean, default: false)
        end
      end

      it 'parses "true"' do
        setup_sprocket_enabled! 'true'
        SPROCKET_ENABLED.should be_true
      end

      it 'parses "false"' do
        setup_sprocket_enabled! 'false'
        SPROCKET_ENABLED.should be_false
      end

      it 'accepts "1" as true' do
        setup_sprocket_enabled! '1'
        SPROCKET_ENABLED.should be_true
      end

      it 'accepts "0" as false' do
        setup_sprocket_enabled! '0'
        SPROCKET_ENABLED.should be_false
      end
    end

    describe 'integer' do
      def setup_num_threads!(value_string)
        ENV['NUM_THREADS'] = value_string
        Conker.module_eval do
          setup_config! :development, :NUM_THREADS => optional(type: :integer, default: 2)
        end
      end

      it 'parses "42"' do
        setup_num_threads! '42'
        NUM_THREADS.should == 42
      end

      it 'throws an error if the value is not an integer' do
        expect { setup_num_threads! 'one hundred' }.to raise_error(/one hundred/)
      end
    end

    describe 'float' do
      def setup_log_probability!(value_string)
        ENV['LOG_PROBABILITY'] = value_string
        Conker.module_eval do
          setup_config! :development, :LOG_PROBABILITY => optional(type: :float, default: 1.0)
        end
      end

      it 'parses "0.5"' do
        setup_log_probability! '0.5'
        LOG_PROBABILITY.should == 0.5
      end

      it 'throws an error if the value is not a float' do
        expect { setup_log_probability! 'zero' }.to raise_error(/zero/)
      end
    end

    describe 'url' do
      def setup_api_url!(value_string)
        ENV['API_URL'] = value_string
        Conker.module_eval do
          setup_config! :development, :API_URL => optional(type: :url, default: 'http://example.com/foo')
        end
      end

      it 'exposes a URI object, not a string' do
        setup_api_url! 'http://localhost:4321/'
        API_URL.host.should == 'localhost'
      end

      it 'parses the default value too' do
        setup_api_url! nil
        API_URL.host.should == 'example.com'
      end
    end

    describe 'addressable' do
      def setup_api_url!(value_string)
        ENV['API_URL'] = value_string
        Conker.module_eval do
          setup_config! :development, :API_URL => optional(type: :addressable, default: 'http://example.com/foo')
        end
      end

      it 'exposes an Addressable::URI object, not a string' do
        setup_api_url! 'http://localhost:4321/'
        API_URL.host.should == 'localhost'
      end

      it 'parses the default value too' do
        setup_api_url! nil
        API_URL.host.should == 'example.com'
      end
    end

    describe 'timestamp' do
      xit 'seems to have bit rotted'
    end
  end
end
