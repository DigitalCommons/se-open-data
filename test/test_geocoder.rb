
require 'se_open_data/config'
require 'se_open_data/csv/geoapify_standard'
require 'se_open_data/utils/password_store'
require 'minitest/autorun'

# Tests for {SeOpenData::CSV::Schema::Types}.

Minitest::Test::make_my_diffs_pretty!

DataDir = __dir__+"/data"

#def read_data(file)
#  CSV.read(DataDir+"/"+file, headers: true).to_a.transpose
#end

#def write_data(file, *rows)
#  CSV.open(DataDir+"/"+file, 'w') do |csv|
#    rows.transpose.each do |row|
#      csv << row
#    end
#  end
#end

pass = SeOpenData::Utils::PasswordStore.new
api_key = pass.get 'geoapifyAPI.txt' # config.GEOCODER_API_KEY_PATH


describe SeOpenData::CSV::Standard::GeoapifyStandard do

#  describe "basic" do
#    #config = SeOpenData::Config.load
#    geocoder = SeOpenData::CSV::Standard::GeoapifyStandard::Geocoder.new(api_key)
#    search_key = 'PO Box 767, Tanunda, Saudi Arabia, 5352, Australia'
#    country = 'Saudi Arabia'
#    cached_entry = geocoder.get_new_data(search_key, country)
#    puts cached_entry
#    it "should er.." do
#      true
#    end
#  end
  
  describe "basic2" do
    cachefile = '/tmp/geocoder_cache' # FIXME hack!
    geocoder = SeOpenData::CSV::Standard::GeoapifyStandard::Geocoder.new(api_key)
    global_postcode_client = SeOpenData::RDF::OsPostcodeGlobalUnit::Client.new(cachefile, geocoder)

    address = ['PO Box 767','Tanunda', 'SA', '5352']
    country = 'AU'
    pcunit = global_postcode_client.get(address, country)
    
    #config = SeOpenData::Config.load
    puts pcunit
    it "should er.." do
      true
    end
  end
end

