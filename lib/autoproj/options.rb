module Autoproj
    class InputError < RuntimeError; end

    class << self
        # Programatically overriden autoproj options
        #
        # @see override_option
        attr_reader :option_overrides
    end
    @option_overrides = Hash.new

    # Programatically override a user-selected option without changing the
    # configuration file
    def self.override_option(option_name, value)
        @option_overrides[option_name] = value
    end

    class BuildOption
        attr_reader :name
        attr_reader :type
        attr_reader :options

        attr_reader :validator

        TRUE_STRINGS = %w{on yes y true}
        FALSE_STRINGS = %w{off no n false}
        def initialize(name, type, options, validator)
            @name, @type, @options = name.to_str, type.to_str, options.to_hash
            @validator = validator.to_proc if validator
            if !BuildOption.respond_to?("validate_#{type}")
                raise ConfigError.new, "invalid option type #{type}"
            end
        end

        def short_doc
            if short_doc = options[:short_doc]
                short_doc
            elsif doc = options[:doc]
                if doc.respond_to?(:to_ary) then doc.first
                else doc
                end
            else "#{name} (no documentation for this option)"
            end
        end

        def doc
            doc = (options[:doc] || "#{name} (no documentation for this option)")
            if doc.respond_to?(:to_ary) # multi-line
                first_line = doc[0]
                remaining = doc[1..-1]
                if remaining.empty?
                    first_line
                else
                    remaining = remaining.join("\n").split("\n").join("\n    ")
                    Autoproj.color(first_line, :bold) + "\n    " + remaining
                end
            else
                doc
            end
        end

        def ask(current_value, doc = nil)
            default_value =
		if !current_value.nil? then current_value.to_s
		elsif options[:default] then options[:default].to_str
		else ''
		end

            STDOUT.print "  #{doc || self.doc} [#{default_value}] "
            STDOUT.flush
            answer = STDIN.readline.chomp
            if answer == ''
                answer = default_value
            end
            validate(answer)

        rescue InputError => e
            Autoproj.message("invalid value: #{e.message}", :red)
            retry
        end

        def validate(value)
            value = BuildOption.send("validate_#{type}", value, options)
            if validator
                value = validator[value]
            end
            value
        end

        def self.validate_boolean(value, options)
            if TRUE_STRINGS.include?(value.downcase)
                true
            elsif FALSE_STRINGS.include?(value.downcase)
                false
            else
                raise InputError, "invalid boolean value '#{value}', accepted values are '#{TRUE_STRINGS.join(", ")}' for true, and '#{FALSE_STRINGS.join(", ")} for false"
            end
        end

        def self.validate_string(value, options)
            if possible_values = options[:possible_values]
                if options[:lowercase]
                    value = value.downcase
                elsif options[:uppercase]
                    value = value.upcase
                end

                if !possible_values.include?(value)
                    raise InputError, "invalid value '#{value}', accepted values are '#{possible_values.join("', '")}' (without the quotes)"
                end
            end
            value
        end
    end

    @user_config = Hash.new

    def self.option_set
        @user_config.inject(Hash.new) do |h, (k, v)|
            h[k] = v.first
            h
        end
    end

    def self.reset_option(key)
        @user_config.delete(key)
    end

    def self.change_option(key, value, user_validated = false)
        @user_config[key] = [value, user_validated]
    end

    def self.user_config(key)
        value, seen = @user_config[key]
        # All non-user options are always considered as "seen"
        seen ||= !@declared_options.has_key?(key)

        if value.nil? || (!seen && Autoproj.reconfigure?)
            value = configure(key)
        else
            if !seen
                doc = @declared_options[key].short_doc
                if doc[-1, 1] != "?"
                    doc = "#{doc}:"
                end
                Autoproj.message "  #{doc} #{value}"
                @user_config[key] = [value, true]
            end
            value
        end
    end

    @declared_options = Hash.new
    def self.configuration_option(name, type, options, &validator)
        @declared_options[name] = BuildOption.new(name, type, options, validator)
    end

    def self.declared_option?(name)
	@declared_options.has_key?(name)
    end

    def self.configure(option_name)
        if opt = @declared_options[option_name]
            if current_value = @user_config[option_name]
                current_value = current_value.first
            end
            value = opt.ask(current_value)
            @user_config[option_name] = [value, true]
            value
        else
            raise ConfigError.new, "undeclared option '#{option_name}'"
        end
    end

    def self.save_config
        File.open(File.join(Autoproj.config_dir, "config.yml"), "w") do |io|
            config = Hash.new
            @user_config.each_key do |key|
                config[key] = @user_config[key].first
            end

            io.write YAML.dump(config)
        end
    end

    def self.has_config_key?(name)
        @user_config.has_key?(name)
    end

    def self.load_config
        config_file = File.join(Autoproj.config_dir, "config.yml")
        if File.exists?(config_file)
            config = YAML.load(File.read(config_file))
            if !config
                return
            end

            config.each do |key, value|
                @user_config[key] = [value, false]
            end
        end
    end

    class << self
        attr_accessor :reconfigure
    end
    def self.reconfigure?; @reconfigure end
end

