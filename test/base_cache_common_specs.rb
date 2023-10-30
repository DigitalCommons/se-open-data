require 'minitest/autorun'

# Resuable specs for BaseCache derivatives
module BaseCacheCommonSpecs
  # This exects subject to be a cache instance
  def self.simple_usecases
    describe "simple usecases" do
      describe "with an apple and a banana" do
        let(:cache) do
          subject["apple"] = "alpha"
          subject["banana"] = "beta"
          subject
        end
        
        it "should contain two items" do
          value(cache.hash.size).must_equal(2)
        end

        it "should contain an apple and a banana only" do
          value(cache["apple"]).must_equal("alpha")
          value(cache["banana"]).must_equal("beta")
          value(cache["carrot"]).must_be_nil
        end

        it "it should only contain the banana item after removing the apple" do
          cache.del("apple")
          value(cache.hash.size).must_equal(1)
          value(cache["apple"]).must_be_nil
          value(cache["banana"]).must_equal("beta")
          value(cache["carrot"]).must_be_nil
        end
      end
    end
  end

  # This expects subject and cache2 to be cache instances
  def self.save_load_usecases(path)
    describe 'loading and saving' do
      let(:cache) do
        subject["apple"] = "alpha"
        subject["banana"] = "beta"
        subject
      end
      
      it 'should save and load' do

        cache.save(path)

        cache2.load(path)

        # check the size and content are correct
        value(cache2.hash.size).must_equal(2)
        value(cache2.hash).must_equal(cache.hash)

        # Add a new entry and save to the default location
        cache["carrot"] = "gamma"
        cache.save

        # Should still be equal
        cache2.load(path)
        value(cache2.hash.size).must_equal(3)
        value(cache2.hash).must_equal(cache.hash)
      end
    end
  end
end
