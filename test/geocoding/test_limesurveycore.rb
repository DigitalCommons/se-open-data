require_relative "../../lib/load_path"
require "se_open_data/config"
require "se_open_data/csv/schemas"
require "se_open_data/csv/standard"
#require "se_open_data/csv/converter/limesurveycore"
require "se_open_data/utils/password_store"
require "minitest/autorun"
require "fileutils"
require "csv"

Minitest::Test::make_my_diffs_pretty!

StdSchema3 = SeOpenData::CSV::Schemas::Versions[2]
StdSchema4 = SeOpenData::CSV::Schemas::Versions[3]

# Hack the latest schema to be something which works with the LimeSurveyCore class implementation
# cos latest Latest doesn't
module SeOpenData::CSV::Schemas
  Latest = ::StdSchema3
end

# Create a dumb stub for Config
Config = Class.new OpenStruct do
  define_method(:fetch) do |n,m|
    if self.respond_to?(n.to_sym)
      self[n]
    else m
    end
  end
end


describe "SeOpenData::CSV::Converter::LimeSurveyCore" do

  caller_dir = File.absolute_path(__dir__)
  data_dir = caller_dir+"/source-data"
  generated_dir = caller_dir+"/generated-data"
  FileUtils.rm_r generated_dir if File.exist? generated_dir
  FileUtils.mkdir_p generated_dir

  api_key_id  ='geoapifyAPI.txt'
  
  llcache = '../open-data/caches/postcode_lat_lng.json'
  pgcache = '../open-data/caches/geodata_cache.json'
  
  describe "Oxford LimeSurveyCore regression test" do
    config = Config.new
    config.SRC_CSV_DIR = data_dir;
    config.ORIGINAL_CSV = 'oxford-input.csv'
    config.GEN_CSV_DIR = generated_dir
    config.STANDARD_CSV = File.join(generated_dir, 'oxford-output.csv')
    config.GEOCODER_API_KEY_PATH = api_key_id
    config.USE_ENV_PASSWORDS = true
    config.ORIGINAL_CSV_SCHEMA = File.join(data_dir, 'oxford-schema.yml')
    config.POSTCODE_LAT_LNG_CACHE = llcache;
    config.GEODATA_CACHE = pgcache;
    
    converted = File.join(data_dir, config.ORIGINAL_CSV)
    output = config.STANDARD_CSV
    expected = File.join(data_dir, "oxford-expected.csv")

    SeOpenData::CSV::Converter::LimeSurveyCore.convert(config);
     
    it "should generate ther expected output file" do
      value(CSV.read(output)).must_equal CSV.read(expected)
    end

  end

end
