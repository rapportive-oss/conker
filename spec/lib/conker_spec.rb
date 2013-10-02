require 'active_support/core_ext/hash/indifferent_access'
$:.unshift File.expand_path("../../lib", __FILE__)
require 'conker'

describe Conker do
  before :each do
    @constants = Kernel.constants
  end

  def fixture(filename)
    File.join(File.dirname(__FILE__), '..', 'fixtures', filename)
  end

  after :each do
    # Don't need to worry about changing (rather than adding) constants,
    # because Ruby will whinge if we do that.
    (Kernel.constants - @constants).each do |k|
      Kernel.send :remove_const, k
    end
  end

  describe 'type: :ip_address' do
    it 'should parse IP addresses' do
      Conker.module_eval do
        setup_config! :development, {"IP_ADDR" => "172.17.16.15"},
                      IP_ADDR: optional(type: :ip_address, default: nil)
      end
      ::IP_ADDR.should == IPAddr.new("172.17.16.15")
    end
  end

  describe 'type: :ip_range' do
    it 'should parse CIDR ranges' do
      Conker.module_eval do
        setup_config! :development, {"IP_RANGE" => "172.17.16.0/24"},
                      IP_RANGE: optional(type: :ip_range, default: nil)

      end
      ::IP_RANGE.should include IPAddr.new("172.17.16.15")
    end

    it 'should parse <from>..<to>' do
      Conker.module_eval do
        setup_config! :development, {"IP_RANGE" => "172.17.16.116..172.17.16.131"},
                      IP_RANGE: optional(type: :ip_range, default: nil)

      end
      ::IP_RANGE.should include IPAddr.new("172.17.16.128")
    end
  end

  describe 'type: :hash' do
    before do
      fixture_path = fixture('hash.yml')
      Conker.module_eval do
        setup_config! :development, fixture_path,
                      CERTIFICATES: optional(type: :hash, default: {})
      end
    end

    it 'should allow indifferent access to symbols' do
      ::CERTIFICATES[:foobar1].should == 'a'
      ::CERTIFICATES['foobar1'].should == 'a'
    end

    it 'should allow indifferent access to strings' do
      ::CERTIFICATES[:foobar2].should == 'b'
      ::CERTIFICATES['foobar2'].should == 'b'
    end

    it 'should allow indifferent access to string that look like symbols' do
      ::CERTIFICATES[:foobar3].should == 'c'
      ::CERTIFICATES['foobar3'].should == 'c'
    end
  end

  describe 'reading config from a hash' do
    describe 'basic usage' do
      def setup!(env = :development, config = {})
        Conker.module_eval do
          setup_config! env, config.with_indifferent_access,
                        A_SECRET: api_credential(development: nil),
                        PORT: required_in_production(type: :integer, default: 42)
        end
      end

      it 'exposes declared variables as top-level constants' do
        setup!
        ::A_SECRET.should be_nil
        ::PORT.should == 42
      end

      it 'lets values in the hash override defaults' do
        setup! :development, PORT: 3000
        ::PORT.should == 3000
      end

      it 'ignores environment variables' do
        ENV['A_SECRET'] = 'beefbeefbeefbeef'
        begin setup! ensure ENV.delete('A_SECRET') end
        ::A_SECRET.should be_nil
      end

      it 'does not turn random environment variables into constants' do
        ENV['PATH'].should_not be_empty
        setup!
        expect { ::PATH }.to raise_error(NameError, /PATH/)
      end

      it 'throws useful errors if required variables are missing' do
        expect { setup! :production, PORT: 42 }.to raise_error(/A_SECRET/)
      end
    end


    describe 'required variables' do
      def setup!(config = {})
        env = @env # capture it for block scope
        Conker.module_eval do
          setup_config! env, config.with_indifferent_access,
            APPNAME: optional(default: 'conker'),
            PORT: required_in_production(type: :integer, default: 3000)
        end
      end

      describe 'in development' do
        before { @env = :development }

        it 'allows optional variables to be missing' do
          expect { setup! PORT: 80 }.not_to raise_error
        end

        it 'allows required_in_production variables to be missing' do
          expect { setup! APPNAME: 'widget' }.not_to raise_error
        end
      end

      describe 'in production' do
        before { @env = :production }

        it 'allows optional variables to be missing' do
          expect { setup! PORT: 80 }.not_to raise_error
        end

        it 'throws a useful error if required_in_production variables are missing' do
          expect { setup! APPNAME: 'widget' }.to raise_error(/PORT/)
        end
      end
    end


    describe 'defaults' do
      def setup!(env = :development, config = {})
        Conker.module_eval do
          setup_config! env, config.with_indifferent_access,
                        NUM_THREADS: optional(type: :integer, test: 1, default: 2)
        end
      end

      it 'uses the specified value if one is given' do
        setup! :development, NUM_THREADS: 4
        NUM_THREADS.should == 4
      end

      it 'uses the default value if none is specified' do
        setup! :development
        NUM_THREADS.should == 2
      end

      it 'allows overriding defaults for specific environments' do
        setup! :test
        NUM_THREADS.should == 1
      end
    end


    describe 'typed variables' do
      describe 'boolean' do
        def setup_sprocket_enabled!(value_string)
          Conker.module_eval do
            setup_config! :development, {'SPROCKET_ENABLED' => value_string},
                          SPROCKET_ENABLED: optional(type: :boolean, default: false)
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
          Conker.module_eval do
            setup_config! :development, {'NUM_THREADS' => value_string},
                          NUM_THREADS: optional(type: :integer, default: 2)
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
          Conker.module_eval do
            setup_config! :development, {'LOG_PROBABILITY' => value_string},
                          LOG_PROBABILITY: optional(type: :float, default: 1.0)
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
          Conker.module_eval do
            setup_config! :development, {'API_URL' => value_string},
                          API_URL: optional(type: :url, default: 'http://example.com/foo')
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
          Conker.module_eval do
            setup_config! :development, {'API_URL' => value_string},
                          API_URL: optional(type: :addressable, default: 'http://example.com/foo')
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


  describe 'reading config from environment variables' do
    before :each do
      @env_vars = ENV.keys
    end

    after :each do
      # N.B. this doesn't catch if we *changed* any env vars (rather than adding
      # new ones).
      (ENV.keys - @env_vars).each {|k| ENV.delete k }
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
  end


  describe 'reading config from a YAML file' do
    describe 'basic usage' do
      def setup!(env = :development, filename = 'empty.yml')
        fixture_path = fixture(filename)
        Conker.module_eval do
          setup_config! env, fixture_path,
                        A_SECRET: api_credential(development: nil),
                        PORT: required_in_production(type: :integer, default: 42)
        end
      end

      it 'exposes declared variables as top-level constants' do
        setup!
        ::A_SECRET.should be_nil
        ::PORT.should == 42
      end

      it 'lets values in the file override defaults' do
        setup! :development, 'port_3000.yml'
        ::PORT.should == 3000
      end

      it 'ignores environment variables' do
        ENV['A_SECRET'] = 'beefbeefbeefbeef'
        begin setup! ensure ENV.delete('A_SECRET') end
        ::A_SECRET.should be_nil
      end

      it 'does not turn random environment variables into constants' do
        ENV['PATH'].should_not be_empty
        setup!
        expect { ::PATH }.to raise_error(NameError, /PATH/)
      end

      it 'throws useful errors if required variables are missing' do
        expect { setup! :production, 'port_3000.yml' }.to raise_error(/A_SECRET/)
      end
    end
  end
end
