require "se_open_data/csv/schema/types"
require "minitest/autorun"
require "csv"

# Tests for {SeOpenData::CSV::Schema::Types}.

Minitest::Test::make_my_diffs_pretty!

DataDir = __dir__+"/data"

def read_data(file)
  CSV.read(DataDir+"/"+file, headers: true).to_a.transpose
end

def write_data(file, *rows)
  CSV.open(DataDir+"/"+file, 'w') do |csv|
    rows.transpose.each do |row|
      csv << row
    end
  end
end

describe SeOpenData::CSV::Schema::Types do

  # A convenient alias
  T = SeOpenData::CSV::Schema::Types

 
  describe "normalise_url" do

    # The data file should have a column with the URLs to test, and a
    # second with the expected normalised urls.
    urls, expected = read_data "urls.csv"

    it "normalise_url should normalise these URLs consistently" do
      normalised = urls.collect do |row|
        T.normalise_url(row)
      end

      # Enable condition to regenerate the url file to match the
      # current algorithm, but remember to set it back, and check the
      # normalisation is correct manually before committing it for
      # future use!
      write_data "urls.csv", urls, normalised if false
      value(normalised).must_equal expected
    end
  end
  
  describe "normalise_facebook" do

    # The data file should have a column with the URLs to test, and a
    # second with the expected normalised urls.
    urls, expected = read_data "facebooks.csv"

    it "normalise_facebook should normalise these URLs consistently" do
      normalised = urls.collect do |row|
        T.normalise_facebook(row)
      end

      # Enable condition to regenerate the url file to match the
      # current algorithm, but remember to set it back, and check the
      # normalisation is correct manually before committing it for
      # future use!
      write_data "facebooks.csv", urls, normalised if false
      value(normalised).must_equal expected
    end
    

  end

end

