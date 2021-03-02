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
  FileUtils.rm_r generated_dir if File.exist? generated_dir
  FileUtils.mkdir_p generated_dir

  # Get the Geoapify API key
  pass = SeOpenData::Utils::PasswordStore.new(use_env_vars: true)
  api_key = pass.get 'geoapifyAPI.txt'
  
  llcache = '../../../../caches/postcode_lat_lng.json'
  pgcache = '../../../../caches/geodata_cache.json'
  
  describe "ICA data geocoding" do
    converted = File.join(data_dir, "ica-input.csv")
    output = File.join(generated_dir, "ica-output.csv")
    expected = File.join(data_dir, "ica-expected.csv")

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

  describe "DotCoop data geocoding" do
    converted = File.join(data_dir, "dotcoop-input.csv")
    output = File.join(generated_dir, "dotcoop-output.csv")
    expected = File.join(data_dir, "dotcoop-expected.csv")

    SeOpenData::CSV.add_postcode_lat_long(infile: converted,
                                          outfile: output,
                                          api_key: api_key,
                                          lat_lng_cache: llcache,
                                          postcode_global_cache: pgcache,
                                          replace_address: "force")
     
    it "should generate ther expected output file" do
      value(CSV.read(output)).must_equal CSV.read(expected)
    end

  end


end
