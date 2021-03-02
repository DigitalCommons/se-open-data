require_relative "../../lib/load_path"
require "se_open_data/config"
require "se_open_data/csv/add_postcode_lat_long"
require "se_open_data/utils/password_store"
require "minitest/autorun"
require "fileutils"
require "csv"

Minitest::Test::make_my_diffs_pretty!


describe "SeOpenData::CSV::add_postcode_lat_long" do

  caller_dir = File.absolute_path(__dir__)
  data_dir = caller_dir+"/source-data"
  generated_dir = caller_dir+"/generated-data"
  FileUtils.mkdir_p generated_dir
  
  describe "ICA data geocoding" do
    config_map = nil
    
    # TestConfig should recreate this + some contents
#    FileUtils.rm_r generated_dir if File.exist? generated_dir

    converted = File.join(data_dir, "input.csv")

    # Output csv file
    output = File.join(generated_dir, "output.csv")
    expected = File.join(data_dir, "expected.csv")

    # Get the Geoapify API key
    pass = SeOpenData::Utils::PasswordStore.new(use_env_vars: true)
    api_key = pass.get 'geoapifyAPI.txt'
    llcache = '../../../../caches/postcode_lat_lng.json'
    pgcache = '../../../../caches/geodata_cache.json'
    SeOpenData::CSV.add_postcode_lat_long(infile: converted,
                                          outfile: output,
                                          api_key: api_key,
                                          lat_lng_cache: llcache,
                                          postcode_global_cache: pgcache,
                                          replace_address: false)
     
    it "should generate ther expected output file" do
      value(CSV.read(output)).must_equal CSV.read(expected)
    end

  end

end
