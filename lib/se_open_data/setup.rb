
require 'se_open_data/config'
require 'se_open_data/csv/schema'
require 'se_open_data/csv/schemas'
require 'se_open_data/csv/schema/types'
require 'se_open_data/geocoding'
require 'se_open_data/utils/file_cache'
require 'se_open_data/utils/password_store'

module SeOpenData

  # A class to assist converter (and other) scripts and avoid boilerplate code
  #
  # Uses the Config and lazily initialises common services required by
  # the converter (and other) scripts on demand.
  #
  # Given an Observer class derived from
  # SeOpenData::CSV::Schema::Observer which can set itself up using an
  # instance of this class given as the `setup` option to its
  # initializer, you should be able to convert CSV files simply, using:
  #
  #    SeOpenData::Setup.new.convert_with(observer: Observer)
  #
  # This will:
  # - load the SeOpenData::Config
  # - create the schemas using the config values / defaults
  # - create a geocoder using the configured values / defaults
  # - instantiate an Observer, passing the setup object to the initializer
  # - create a SeOpenData::CSV::Schema::Converter and use that with the
  #   observer to do the conversion, to the configured output file
  #
  # This class is designed to allow easy subclassing to override some
  # of the logic should the defaults be inconvenient.
  class Setup
    attr_accessor :from_schema, :to_schema, :config
                                  
    # Constructor
    #
    # See also {SeOpenData::Config} for information about the settings used in this class
    def initialize(config: SeOpenData::Config.load,
                   from_schema: nil,
                   to_schema: nil,
                   geocoder_api_key: nil)
      @config = config
      @from_schema = from_schema
      @to_schema = to_schema
      @geocoder_api_key = geocoder_api_key
    end

    # Gets the first existing file of the list given as parameters.
    # If none exist, return the default.
    def self.first_existing(*files, default: nil)
      files.find {|it| File.exist? it } || default
    end
    
    # This defines the input CSV schema we expect (after clean-up an index generation)
    def from_schema
      _from_schema_file = from_schema_file
      @from_schema ||= if _from_schema_file
                         SeOpenData::CSV::Schema.load_file(_from_schema_file)
                       else
                         raise ArgumentError, "No input schema file found"
                       end
    end

    def from_schema=(value)
      @from_schema = value
    end
    
    # This defines the output CSV schema we expect
    def to_schema
      _to_schema_file = to_schema_file
      @to_schema ||= if _to_schema_file
                       SeOpenData::CSV::Schema.load_file(_to_schema_file)
                     else
                       SeOpenData::CSV::Schemas::Latest;
                     end
    end

    def to_schema=(value)
      @to_schema = value
    end
    
    # The list of files to search for an input schema definition
    def from_schema_files
      @from_schema_files ||= %w(schema.yaml schema.yml schema.csv
                                 input.yaml input.yml input.csv)
    end
    
    def from_schema_files=(value)
      @from_schema_files = value
    end
    
    # The list of files to search for an output schema definition
    def to_schema_files
      @to_schema_files ||= %w(output.yaml output.yml output.csv)
    end

    def to_schema_files=(value)
      @to_schema_files = value
    end
    
    # The path of the original data file (which is typically CSV but doesn't have to be)
    def input_file
      @input_file ||= File.join(@config.SRC_CSV_DIR, @config.ORIGINAL_CSV)
    end

    def input_file=(value)
      @input_file = value
    end
    
    # The path of the output data file, which is a CSV
    def output_file
      @output_file ||= @config.STANDARD_CSV
    end

    def output_file=(value)
      @output_file = value
    end

    # The path of the input scheme definition
    def from_schema_file
      @from_schema_file ||= self.class.first_existing(*from_schema_files)
    end

    def from_schema_file=(value)
      @from_schema_file = value
    end
    
    # The path of the output scheme definition (if null,
    # SeOpenData::CSV::Schemas::Latest is used)
    def to_schema_file
      @to_schema_file ||= self.class.first_existing(*to_schema_files)
    end

    def to_schema_file=(value)
      @to_schema_file = value
    end

    # Gets the configured geocoder (but doesn't set it as the default)
    def get_geocoder(id: nil, api_key: nil, cache: nil)
      id ||= @config.fetch('GEOCODER', :geoapify).to_sym # default is :geoapify
      api_key ||= geocoder_api_key
      cache ||= file_cache
      SeOpenData::Geocoding.new.build(
        lookup: id,
        api_key: api_key,
        cache: cache,
      )
    end

    # Gets and stores the default geocoder
    def geocoder
      @geocoder ||= get_geocoder
    end

    def geocoder=(value)
      @geocoder=value
    end

    # Get a SeOpenData::Utils::FileCache instance
    def file_cache
      @file_cache ||= SeOpenData::Utils::FileCache.new.load(@config.GEODATA_CACHE)
    end

    def file_cache=(value)
      @file_cache = value
    end
    
    # Get a password store instance which can be used to retrieve secrets
    def pass
      @pass ||= SeOpenData::Utils::PasswordStore.new(use_env_vars: @config.USE_ENV_PASSWORDS)
    end

    def pass=(value)
      @pass = value
    end

    # Get the Geocoder API key from the password store
    def geocoder_api_key
      @geocoder_api_key ||= pass.get @config.GEOCODER_API_KEY_PATH 
    end

    # Gets the default input CSV opts
    def input_csv_opts
      @input_csv_opts ||= {skip_blanks: true}
    end

    def input_csv_opts=(value)
      @input_csv_opts = value
    end
    
    # Gets the default output CSV opts
    def output_csv_opts
      {quote_empty: false}
    end
    
    def output_csv_opts=(value)
      @output_csv_opts = value
    end
    
    # Convert the data using this observer given
    #
    # observer - an observer instance to use, or a Class to instantiate
    # with obserever.new(setup:), passing this as the setup option.
    def convert_with(observer:)
      if observer.is_a? Class
        observer = observer.new(setup: self)
      end
      
      # A converter between the input and standard csv schema
      converter = SeOpenData::CSV::Schema::Converter.new(
        from_schema: from_schema,
        to_schema: to_schema,
        input_csv_opts: input_csv_opts,
        output_csv_opts: output_csv_opts,
        observer: observer
      )
      
      # Convert the csv to the standard schexma
      converter.convert File.open(input_file), output_file

      return self
    rescue => e
      raise "error transforming {input_file} into {output_file}: #{e.message}"
    end
  end
end
