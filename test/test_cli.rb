# coding: utf-8
require 'se_open_data/cli'
require 'minitest/autorun'
require 'linkeddata'

# Tests for SeOpenData::VocabToIndex.

Minitest::Test::make_my_diffs_pretty!

# convenience function - sets the working directory temporarily
def setpwd
  testscripts_dir = File.join(__dir__, 'scripts')
  Dir.chdir(testscripts_dir) do
    yield
  end
end

# convenience function - runs the method, but shorter
def invoke(arg, **opts)
  SeOpenData::CliHelper.invoke_script(arg, **opts)
end

describe SeOpenData::CliHelper do
  
  describe "#invoke_script" do

    it "should follow the default behaviour" do
      setpwd do
        value(invoke "testscript 0").must_equal true
        value { invoke "testscript 1" }.must_raise
        value { invoke "nonsuchscript" }.must_raise
      end
    end

    # The following attempts to be exhaustive in the permutations
    
    it "when script succeeds" do
      setpwd do
        value(invoke "testscript 0",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: nil).must_equal true
        value(invoke "testscript 0",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: 1).must_equal true
        value(invoke "testscript 0",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: nil).must_equal true
        value(invoke "testscript 0",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: 1).must_equal true
        value(invoke "testscript 0",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: nil).must_equal true
        value(invoke "testscript 0",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: 1).must_equal true
        value(invoke "testscript 0",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: nil).must_equal true
        value(invoke "testscript 0",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: 1).must_equal true
      end
    end
    
    it "when script fails" do
      setpwd do
        value{invoke "testscript 255",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: nil}.must_raise
        value{invoke "testscript 255",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: 1}.must_raise
        value(invoke "testscript 255",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: 255).must_equal 255
        value(invoke "testscript 255",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: nil).must_equal false
        value(invoke "testscript 255",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: 255).must_equal 255
        value{invoke "testscript 255",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: nil}.must_raise
        value(invoke "testscript 255",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: 255).must_equal 255
        value(invoke "testscript 255",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: nil).must_equal false
        value(invoke "testscript 255",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: 1).must_equal false
        value(invoke "testscript 255",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: 255).must_equal 255
      end
    end
      
    it "when script absent" do
      setpwd do
        value{invoke "nonesuch 0",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: nil}.must_raise
        value{invoke "nonesuch 0",
                     allow_absent: false,
                     allow_failure: false,
                     allow_codes: 1}.must_raise
        value{invoke "nonesuch 0",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: nil}.must_raise
        value{invoke "nonesuch 0",
                     allow_absent: false,
                     allow_failure: true,
                     allow_codes: 1}.must_raise
        value(invoke "nonesuch 0",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: nil).must_be_nil
        value(invoke "nonesuch 0",
                     allow_absent: true,
                     allow_failure: false,
                     allow_codes: 1).must_be_nil
        value(invoke "nonesuch 0",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: nil).must_be_nil
        value(invoke "nonesuch 0",
                     allow_absent: true,
                     allow_failure: true,
                     allow_codes: 1).must_be_nil
      end
    end
  end
end

