require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/hash/reverse_merge'
require 'addressable/uri'

# Example use:
#     module Conker
#       setup_config!(Rails.env, :A_SECRET => api_credential)
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


  class << self
    # Parse a multi-key hash into globals and raise an informative error message on failure.
    def setup_config!(current_env, *args)
      hash = args.extract_options!
      config = args[0] || ENV

      errors = []
      hash.each do |varname, declaration|
        begin
          Kernel.const_set(varname, declaration.evaluate(current_env, config, varname.to_s))
        rescue => error
          errors << [varname, error.message]
        end
      end

      error_message = errors.sort_by {|v, e| v.to_s }.map do |varname, error|
        varname.to_s + ': ' + error
      end.join(", ")
      raise Error, error_message unless errors.empty?
    end

    # A wrapper around setup_config! that uses ENV["RACK_ENV"] || 'development'
    def setup_rack_environment!(hash)
      ENV["RACK_ENV"] ||= 'development'

      setup_config!(ENV["RACK_ENV"],
                    hash.merge(:RACK_ENV => required_in_production(:development => 'development', :test => 'test')))
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

    # Declare an environment variable, defaulting to other values if not defined.
    #
    # You must either specify a :default, or specify defaults for each of
    # :production, :test and :development.
    def optional(declaration_opts = {})
      VariableDeclaration.new(declaration_opts)
    end
  end


  class VariableDeclaration
    def initialize(declaration_opts)
      declaration_opts.assert_valid_keys :required_in, :type, :default, *ENVIRONMENTS.map(&:to_sym)
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
      if @config[varname] && @environment != 'test'
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
        value.to_s.downcase == "true" || value.to_i == 1
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
      when :timestamp
        raise MustBeDefined if value.nil? # there's nothing sensible to default to.
        Time.iso8601(value.to_s).utc
      when :string, nil
        value.to_s
        # defaults to '' if omitted
      else
        raise UnknownType, type.to_s
      end
    end
  end
end
