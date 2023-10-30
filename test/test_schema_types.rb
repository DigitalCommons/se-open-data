require "se_open_data/csv/schema/types"
require "minitest/autorun"
require "csv"

# Tests for {SeOpenData::CSV::Schema::Types}.

Minitest::Test::make_my_diffs_pretty!

module Data
  Dir = __dir__+"/data"

  def self.read(file)
    CSV.read(Dir+"/"+file, headers: true).to_a.transpose
  end

  def self.write(file, *rows)
    CSV.open(Dir+"/"+file, 'w') do |csv|
      rows.transpose.each do |row|
        csv << row
      end
    end
  end
end

describe SeOpenData::CSV::Schema::Types do

  # A convenient alias
  T = SeOpenData::CSV::Schema::Types

 
  describe "normalise_url" do

    # The data file should have a column with the URLs to test, and a
    # second with the expected normalised urls.
    urls, expected = Data.read "urls.csv"

    it "normalise_url should normalise these URLs consistently" do
      normalised = urls.collect do |row|
        T.normalise_url(row)
      end

      # Enable condition to regenerate the url file to match the
      # current algorithm, but remember to set it back, and check the
      # normalisation is correct manually before committing it for
      # future use!
      Data.write "urls.csv", urls, normalised if false
      value(normalised).must_equal expected
    end
  end
  
  describe "normalise_facebook" do

    # The data file should have a column with the URLs to test, and a
    # second with the expected normalised urls.
    urls, expected = Data.read "facebooks.csv"

    it "normalise_facebook should normalise these URLs consistently" do
      normalised = urls.collect do |row|
        T.normalise_facebook(row)
      end

      # Enable condition to regenerate the url file to match the
      # current algorithm, but remember to set it back, and check the
      # normalisation is correct manually before committing it for
      # future use!
      Data.write "facebooks.csv", urls, normalised if false
      value(normalised).must_equal expected
    end
    

  end
  
  describe "normalise_twitter" do

    # The data file should have a column with the URLs to test, and a
    # second with the expected normalised urls.
    urls, expected = Data.read "twitter.csv"

    it "normalise_twitter should normalise these URLs consistently" do
      normalised = urls.collect do |row|
        T.normalise_twitter(row)
      end

      # Enable condition to regenerate the url file to match the
      # current algorithm, but remember to set it back, and check the
      # normalisation is correct manually before committing it for
      # future use!
      Data.write "twitter.csv", urls, normalised if false
      value(normalised).must_equal expected
    end
  end

end

