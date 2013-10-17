require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/hash/reverse_merge'
require 'addressable/uri'

# Example that uses the process's environment:
#     module Conker
#       setup_config!(Rails.env, :A_SECRET => api_credential)
#     end
#
# Example that uses a supplied hash of values (e.g. read from some file or
# database):
#     config_values = {:A_SECRET => 'very_secret'}
#     module Conker
#       setup_config!(Rails.env, config_values, :A_SECRET => api_credential)
#     end
#
# For convenience, if your config file is YAML, you can supply the path
# directly and Conker will load and parse the file:
#     module Conker
#       setup_config!(Rails.env, 'config_values.yml', :A_SECRET => api_credential)
#     end
module Conker
  ENVIRONMENTS = %w(production development test)
  DUMMY_API_KEY = 'dummy_api_key'.freeze
  DUMMY_CRYPTO_SECRET = 'dummysecretdummysecretdummysecretdummysecretdummysecretdummysecretdummysecre'

  class Error < StandardError; end
  class MustBeDefined < Error
    def initialize; super('must be defined'); end
  end
  class UnknownType < Error
    def initialize(type); super("unknown type #{type}"); end
  end
  class MissingDefault < Error
    def initialize; super("missing default value"); end
  end
  class IncompatibleType < Error; end


  class << self
    # Parse a multi-key hash into globals and raise an informative error message on failure.
    def setup_config!(current_env, *args)
      declarations = args.extract_options!
      values = values_hash(current_env, args[0])

      setup_constants(current_env, declarations, values)
    end

    # Like setup_config! but uses ENV['RACK_ENV'] || 'development' as the
    # environment.  Also sets constant RACK_ENV.
    #
    # N.B. if using this method, you don't need to specify :RACK_ENV in your
    # variable declarations, and it will complain if you do.  This is partly to
    # make clear that this method *won't* read RACK_ENV from your config file,
    # only from the environment variable, for compatibility with other code
    # (e.g. Sinatra) that depends directly on the environment variable.
    def setup_rack_environment!(*args)
      ENV['RACK_ENV'] ||= 'development'
      set_constant(:RACK_ENV, ENV['RACK_ENV'])
      current_env = get_constant(:RACK_ENV)

      declarations = args.extract_options!
      values = values_hash(current_env, args[0])

      if declarations.key?('RACK_ENV') || declarations.key?(:RACK_ENV)
        raise Error, "No need to declare RACK_ENV; please remove it to avoid confusion!"
      end
      if ENV.key?('RACK_ENV') && values.key?('RACK_ENV') && (env = ENV['RACK_ENV']) != (conf = values['RACK_ENV'])
        raise "RACK_ENV differs between environment (#{env}) and config (#{conf})!  Please remove it from your config."
      end

      setup_constants(current_env, declarations, values)
    end

    # Declare an environment variable that is required to be defined in the
    # production environment, and defaults to other values in the test or
    # development environments.
    #
    # You must either specify a :default, or specify defaults for each of
    # :test and :development.
    def required_in_production(declaration_opts={})
      VariableDeclaration.new(declaration_opts.reverse_merge(:required_in => :production))
    end

    # Declare an environment variable to be used as a credential for accessing
    # an external API (e.g. username, password, API key, access token):
    # shorthand for
    # +required_in_production(:type => :string, :default => 'dummy_api_key')+
    def api_credential(declaration_opts={})
      required_in_production({
        :type => :string,
        :default => DUMMY_API_KEY,
      }.merge(declaration_opts))
    end

    # Declare an environment variable to be used as a secret key by some
    # encryption algorithm used in our code.
    #
    # To generate a secret suitable for production use, try:
    #   openssl rand -hex 256
    # (which will generate 256 bytes = 2048 bits of randomness).
    #
    # The distinction between this and api_credential is mainly for
    # documentation purposes, but they also have different defaults.
    def crypto_secret(declaration_opts={})
      required_in_production({
        :type => :string,
        :default => DUMMY_CRYPTO_SECRET,
      }.merge(declaration_opts))
    end

    # A redis url is required_in_production with development and test defaulting to localhost.
    def redis_url(opts={})
      required_in_production({
        :development => "redis://localhost/1",
        :test => "redis://localhost/3"
      }.merge(opts))
    end

    # A couchbase_url is required_in_production with development defaulting to
    # localhost/default and test defaulting to localhost/test.
    def couchbase_url(opts = {})
      required_in_production({
        :development => 'http://localhost:8091/pools/default/buckets/default',
        :test => 'http://localhost:8091/pools/default/buckets/test',
      }.merge(opts))
    end

    # Declare an environment variable, defaulting to other values if not defined.
    #
    # You must either specify a :default, or specify defaults for each of
    # :production, :test and :development.
    def optional(declaration_opts = {})
      VariableDeclaration.new(declaration_opts)
    end

    private
    def values_hash(current_env, values)
      case values
      when Hash; values
      when String
        if File.exist?(values)
          require 'yaml'
          YAML.parse_file(values).to_ruby
        elsif 'production' == current_env.to_s
          raise Error, "Missing config file #{values}"
        else
          {}
        end
      else; ENV
      end
    end

    def setup_constants(current_env, declarations, values)
      errors = []
      declarations.each do |varname, declaration|
        begin
          set_constant(varname, declaration.evaluate(current_env, values, varname.to_s))
        rescue => error
          errors << [varname, error.message]
        end
      end

      error_message = errors.sort_by {|v, e| v.to_s }.map do |varname, error|
        varname.to_s + ': ' + error
      end.join(", ")
      raise Error, error_message unless errors.empty?
    end

    def set_constant(varname, value)
      Kernel.const_set(varname, value)
    end

    def get_constant(varname)
      Kernel.const_get(varname)
    end
  end


  class VariableDeclaration
    def initialize(declaration_opts)
      declaration_opts.assert_valid_keys :required_in, :type, :default, *ENVIRONMENTS.map(&:to_sym), :delimiter
      if declaration_opts.key?(:delimiter) && declaration_opts[:type] != :array
        raise "Unknown key :delimiter for type :#{declaration_opts[:type] || :string}.  Did you mean :type => :array?"
      end
      @declaration_opts = declaration_opts.with_indifferent_access
    end

    def evaluate(current_environment, config, varname)
      @environment = current_environment
      @config = config
      check_missing_value! varname
      check_missing_default!
      from_config_variable_or_default(varname)
    end

    private
    def check_missing_value!(varname)
      if required_in_environments.member?(@environment.to_sym) && !@config[varname]
        raise MustBeDefined
      end
    end

    def check_missing_default!
      environments_needing_default = ENVIRONMENTS.map(&:to_sym) - required_in_environments
      default_specified = @declaration_opts.key? :default
      all_environments_defaulted = environments_needing_default.all?(&@declaration_opts.method(:key?))
      unless default_specified || all_environments_defaulted
        raise MissingDefault
      end
    end

    def from_config_variable_or_default(varname)
      if !@config[varname].nil? && @environment != 'test'
        interpret_value(@config[varname], @declaration_opts[:type])
      else
        default_value
      end
    end

    def required_in_environments
      Array(@declaration_opts[:required_in]).map(&:to_sym)
    end

    # Only interpret the default value if it is a string
    # (to avoid coercing nil to '')
    def default_value
      default = @declaration_opts.include?(@environment) ? @declaration_opts[@environment] : @declaration_opts[:default]
      if default.is_a? String
        interpret_value(default, @declaration_opts[:type])
      else
        default
      end
    end

    def interpret_value(value, type)
      type = type.to_sym if type
      case type
      when :boolean
        if [true, false].include? value
          value
        else
          value.to_s.downcase == "true" || value.to_i == 1
        end
        # defaults to false if omitted
      when :integer
        Integer(value)
        # defaults to 0 if omitted
      when :float
        value ?  Float(value) : 0.0
        # defaults to 0.0 if omitted
      when :url
        raise MustBeDefined if value.nil? # there's nothing sensible to default to
        require 'uri' unless defined? URI
        URI.parse(value.to_s)
      when :addressable
        raise MustBeDefined if value.nil? # there's nothing sensible to default to
        require 'addressable' unless defined? Addressable
        Addressable::URI.parse(value.to_s)
      when :ip_address
        raise MustBeDefined if value.nil? # there's nothing sensible to default to
        require 'ipaddr' unless defined? IPAddr
        IPAddr.new(value.to_s)
      when :ip_range
        raise MustBeDefined if value.nil? # there's nothing sensible to default to
        require 'ipaddr' unless defined? IPAddr

        # Support <from>..<to> for ranges that cannot be specified with CIDR easily.
        if value =~ /\A(.*)\.\.(.*)\z/
          IPAddr.new($1) .. IPAddr.new($2)
        else
          IPAddr.new(value.to_s).to_range
        end
      when :timestamp
        raise MustBeDefined if value.nil? # there's nothing sensible to default to.
        Time.iso8601(value.to_s).utc
      when :string, nil
        value.to_s
        # defaults to '' if omitted
      when :hash
        unless value.is_a? Hash
          raise IncompatibleType, "wanted a Hash, got #{value.class}"
        end
        value.with_indifferent_access
      when :array
        if delimiter = @declaration_opts[:delimiter]
          # e.g. ENV['WIDGET'] = 'foo:bar:baz' # yields ['foo', 'bar', 'baz']
          if value.is_a? String
            value.split(delimiter)
          else
            raise IncompatibleType, "wanted a String to parse :array with :delimiter, got #{value.class}"
          end
        else
          # e.g.
          #   WIDGET: foo # yields WIDGET = ['foo']
          #   WIDGET:
          #     - bar
          #     - baz
          #    # yields WIDGET = ['foo', 'bar']
          Array(value)
        end
      else
        raise UnknownType, type.to_s
      end
    end
  end
end
