module SeOpenData
  # Reads a simple key-value plain-text config file.
  #
  # Values are delimited by an `=` character. Expected values are
  # expanded with some hard-wired know-how, and some directories are
  # found relative to the {base_dir} parameter, which defaults to the
  # caller script's directory.
  #
  # This is an abstraction layer from the config file itself.
  # i.e. Variables here are independant from names in the config file.
  # FIXME expand
  class Config
    require "fileutils"
    require "se_open_data/utils/log_factory"

    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default

    # Where to look for non-code resources
    RESOURCE_DIR = File.expand_path("../../resources", __dir__)

    # Default values for optional key that should not default to nil.
    # Directories which are relative are typically expanded relative
    # to the current working directory.
    DEFAULTS = {
      "AUTO_LOAD_TRIPLETS" => true,
      "CSS_SRC_DIR" => File.join(RESOURCE_DIR, "css"),
      "SRC_CSV_DIR" => "original-data",
      "ORIGINAL_CSV" => "original.csv",
      "ORIGINAL_CSV_SCHEMA" => "schema.yml",
      "STANDARD_CSV" => "standard.csv",
      "TOP_OUTPUT_DIR" => "generated-data",
      "URI_SCHEME" => "https",
      "USE_ENV_PASSWORDS" => false,
      "ESSGLOBAL_URI" => "https://w3id.solidarityeconomy.coop/essglobal/V2a/",
      "DEPLOYMENT_WEB_USER" => "www-data",
      "DEPLOYMENT_WEB_GROUP" => "www-data",
      "VIRTUOSO_USER" => "root",
      "VIRTUOSO_GROUP" => "root",
      "VOCAB_INDEX_FILE" => "vocabs.json",
      "VOCAB_LANGS" => "en",
      "USING_ICA_ACTIVITIES" => false,
    }

    # @param file [String] - the path to the config file to load.
    # @param base_dir [String] - the base directory in which to locate certain paths
    def initialize(file, base_dir = Config.caller_dir)
      @config_file = file

      @map = {}

      File.foreach(@config_file).with_index(1) do |line, num|
        next if line =~ /^\s*$/ # skip blank lines
        next if line =~ /^\s*#/ # skip comments

        # Split on the first =, trim the resulting string pair.
        # If no =, val will be nil.
        key, val = line.split("=", 2).map(&:strip)

        # Guard against invalid key characters. This is almost certainly a mistake
        raise "invalid config key '#{key}' at line #{num}" unless valid_key? key

        # Guard against no '='. Likewise a mistake.
        raise "config line with no '=' delimiter on line #{num}" if val.nil?

        # Guard against duplicates. Likewise a mistake.
        raise "config key '#{key}' duplicated on line #{num}" if @map.has_key? key

        # Add the key and value
        @map[key] = val
      end

      # Add defaults here after the loop, which uses the map to spot
      # duplicates.
      @map = DEFAULTS.merge(@map)

      # These keys are mandatory, because we use them below, or elsewhere
      %w(TOP_OUTPUT_DIR SRC_CSV_DIR STANDARD_CSV
         URI_SCHEME URI_HOST URI_PATH_PREFIX CSS_SRC_DIR
         DEPLOYMENT_WEBROOT VIRTUOSO_ROOT_DATA_DIR
         ESSGLOBAL_URI
         SPARQL_ENDPOINT VIRTUOSO_PASS_FILE)
        .each do |key|
        raise "mandatory key '#{key}' is missing" unless @map.has_key? key
      end

      # Expand these paths relative to base_dir
      %w(TOP_OUTPUT_DIR SRC_CSV_DIR CSS_SRC_DIR)
        .each do |key| # expand rel to base_dir, append a slash
        @map[key] = join File.expand_path(@map[key], base_dir), ""
      end

      # This is the directory where we generate intermediate csv files
      @map["GEN_CSV_DIR"] = join @map["TOP_OUTPUT_DIR"], "csv", ""

      # Final output file (usually "standard.csv")
      @map["STANDARD_CSV"] = join @map["TOP_OUTPUT_DIR"], @map["STANDARD_CSV"]
      #csv.rb end

      unless @map["URI_SCHEME"] =~ /^https?$/
        raise "Invalid URI_SCHEME: must be http or https"
      end
      
      # Clean up these - extra delimiters can cause havoc and be hard to find
      %w(URI_HOST URI_PATH_PREFIX).each do |key|
        # Just remove relatively harmless stuff, superfluous delimiters at the ends
        @map[key] = @map[key]
                      .sub(%r{[ /]+$},'')
                      .sub(%r{^[ /]+},'')
      end
      
      # Used by static data generation
      @map["WWW_DIR"] = unixjoin @map["TOP_OUTPUT_DIR"], "www", ""
      @map["GEN_DOC_DIR"] = unixjoin @map["WWW_DIR"], "doc", ""
      @map["GEN_CSS_DIR"] = unixjoin @map["GEN_DOC_DIR"], "css", ""
      @map["GEN_VIRTUOSO_DIR"] = unixjoin @map["TOP_OUTPUT_DIR"], "virtuoso", ""
      @map["GEN_SPARQL_DIR"] = unixjoin @map["TOP_OUTPUT_DIR"], "sparql", ""
      @map["SPARQL_GET_ALL_FILE"] = unixjoin @map["GEN_SPARQL_DIR"], "query.rq"
      @map["SPARQL_LIST_GRAPHS_FILE"] = unixjoin @map["GEN_SPARQL_DIR"], "list-graphs.rq"
      @map["SPARQL_ENDPOINT_FILE"] = unixjoin @map["GEN_SPARQL_DIR"], "endpoint.txt"
      @map["SPARQL_GRAPH_NAME_FILE"] = unixjoin @map["GEN_SPARQL_DIR"], "default-graph-uri.txt"
      @map["GRAPH_NAME"] = @map["URI_SCHEME"] + "://" + unixjoin(@map["URI_HOST"], @map["URI_PATH_PREFIX"])

      @map["ONE_BIG_FILE_BASENAME"] = unixjoin @map["GEN_VIRTUOSO_DIR"], "all"

      @map["SAME_AS_FILE"] = @map.key?("SAMEAS_CSV") ? @map["SAMEAS_CSV"] : ""
      @map["SAME_AS_HEADERS"] = @map.key?("SAMEAS_HEADERS") ? @map["SAMEAS_HEADERS"] : ""

      # Used by static data deployment
      @map["DEPLOYMENT_DOC_SUBDIR"] = @map["URI_PATH_PREFIX"]
      @map["DEPLOYMENT_DOC_DIR"] = unixjoin @map["DEPLOYMENT_WEBROOT"], @map["DEPLOYMENT_DOC_SUBDIR"]

      # Used by linked-data graph deployment
      @map["VIRTUOSO_NAMED_GRAPH_FILE"] = unixjoin @map["GEN_VIRTUOSO_DIR"], "global.graph"
      @map["VIRTUOSO_SQL_SCRIPT"] = "loaddata.sql"

      @map["VERSION"] = make_version
      @map["VIRTUOSO_DATA_DIR"] = unixjoin @map["VIRTUOSO_ROOT_DATA_DIR"], @map["VERSION"], ""
      @map["VIRTUOSO_SCRIPT_LOCAL"] = join @map["GEN_VIRTUOSO_DIR"], @map["VIRTUOSO_SQL_SCRIPT"]
      @map["VIRTUOSO_SCRIPT_REMOTE"] = unixjoin @map["VIRTUOSO_DATA_DIR"], @map["VIRTUOSO_SQL_SCRIPT"]

      # Preserve booleans in these cases
      %w(AUTO_LOAD_TRIPLETS USE_ENV_PASSWORDS USING_ICA_ACTIVITIES).each do |key|
        @map[key] = @map.key?(key) && @map[key].to_s.downcase == "true"
      end

      @map['VOCAB_LANGS'] = @map['VOCAB_LANGS'].split(/ +/).collect do |val|
        unless val =~ /^[a-z]{2}/
          abort "invalid language code '#{val}': "+
                "VOCAB_LANGS must be > 0 space-delimited 2 character language codes"
        end
        val.downcase.to_sym
      end
      
      # Define an accessor method for all the keys on this instance -
      # but only if they don't exist already
      @map.each_key do |key|
        add_accessor(key)
      end

      # Make sure these dirs exist
      FileUtils.mkdir_p @map.fetch_values(
        "GEN_CSV_DIR",
        "GEN_CSS_DIR",
        "GEN_VIRTUOSO_DIR",
        "GEN_SPARQL_DIR"
      )
    rescue => e
      raise "#{e.message}: #{@config_file}"
    end

    # Checks whether key is valid
    #
    # Valid keys must contain only alphanumeric characters, hyphens or underscores.
    # @return [Boolean] true if it is valid.
    def valid_key?(key)
      key !~ /\W/
    end

    # A convenient method for #map.fetch
    #
    # @param args (See Hash#fetch)
    # @return (See Hash#fetch)
    def fetch(*args)
      @map.fetch(*args)
    end

    # A convenient method for #map.has_key?
    #
    # @param args (See Hash#has_key?)
    # @return (See Hash#has_key?)
    def has_key?(key)
      @map.has_key? key
    end

    # Sets a value in the config
    #
    # Creates it (and an accessor) if it is not already set.
    def store(key, value)
      key = key.to_s
      add_accessor(key) unless @map.has_key? key
      @map.store(key, value)
    end

    # Gets the underlying config hash
    def map
      @map
    end

    protected

    # Add an accessor method named `key` (but only if it isn't defined already)
    def add_accessor(key)
      method = key.to_sym
      if !self.respond_to? method
        define_singleton_method method do
          @map[key]
        end
      end
    end
    
    # For overriding in tests
    def make_version
      t = Time.now
      "#{t.year}#{t.month}#{t.day}#{t.hour}#{t.min}#{t.sec}"
    end

    private

    # Joins directory fragments using local path delimiter
    def join(*args)
      File.join(*args)
    end

    # Joins directory fragments using the unix '/' delimiter
    def unixjoin(first, *rest)
      #First part must have trailing slash removed only, rest must
      # have (a single) leading slash.
      first.gsub(%r{/+$}, "") + rest.map { |it| it.gsub(%r{^/*}, "/") }.join
    end

    # Used only in the constructor as a default value for base_dir
    def self.caller_dir
      File.dirname(caller_locations(2, 1).first.absolute_path)
    end

    # Loads a config file relative to the current working directory
    #
    # The path argument, if supplied, can be a path, filename, or a
    # Dir.glob supported pattern.
    #
    # If a pattern, the first matching file is used.
    #
    # However, if path is nil and an environment variable
    # `SEOD_CONFIG` is set, that is used to set the value path. The
    # same logic above applies.
    #
    # @param path [String] a path to the config file, or a file-glob
    # pattern which expands to more than one path, in order of
    # preference. Relative to the current working directory.
    # @return [SeOpenData::Config]
    def self.load(path = nil, base: Dir.pwd)
      if path == nil
        if ENV.has_key? "SEOD_CONFIG"
          # Use this environment variable to define where the config is
          path = ENV["SEOD_CONFIG"]
        else
          path = "{local,default}.conf"
        end
      end

      config_file = Dir.glob(path, base: base).first # first match
      if config_file.nil?
        raise RuntimeError, "No config file found matching: #{path}"
      end
      Log.info "loading config: #{config_file}"
      return SeOpenData::Config.new(config_file, base)
    end
  end
end
