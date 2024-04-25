require_relative "../../lib/load_path"
require "se_open_data/config"
require "minitest/autorun"
require "fileutils"

Minitest::Test::make_my_diffs_pretty!

# Stubbed subclass for testing
class TestConfig < SeOpenData::Config
  def make_version # prevent this changing second to second
    "2020526214656"
  end
end

describe SeOpenData::Config do
  resource_dir = SeOpenData::Config::RESOURCE_DIR
  caller_dir = File.absolute_path(__dir__)
  generated_dir = caller_dir+"/generated-data"

  describe "a minimal config instance" do
    config_map = nil
    
    # TestConfig should recreate this + some contents
    FileUtils.rm_r generated_dir if File.exist? generated_dir

    # expansions relative to caller_dir, i.e. this script's dir
    config = TestConfig.new(caller_dir+"/config/minimal.txt")

    # Make recursive directory listing here, before other tests delete it
    listing = Dir.glob(generated_dir+"/**/*", File::FNM_DOTMATCH)
                .map {|it| it.delete_prefix(generated_dir)+"\n" }
                .sort
                .join
    
    config_map = config.map
    
    #puts config_map
    expected_map = {
      "AUTO_LOAD_TRIPLETS" => true,
      "CSS_SRC_DIR" => resource_dir + "/css/",
      "SRC_CSV_DIR" => caller_dir + "/original-data/",
      "ORIGINAL_CSV" => "original.csv",
      "ORIGINAL_CSV_SCHEMA" => "schema.yml",
      "STANDARD_CSV" => caller_dir + "/generated-data/standard.csv",
      "TOP_OUTPUT_DIR" => caller_dir + "/generated-data/",
      "URI_SCHEME" => "https",
      "USE_ENV_PASSWORDS" => false,
      "ESSGLOBAL_URI" => "https://w3id.solidarityeconomy.coop/essglobal/V2a/",
      "DEPLOYMENT_WEB_USER" => "www-data",
      "DEPLOYMENT_WEB_GROUP" => "www-data",
      "VIRTUOSO_USER" => "root",
      "VIRTUOSO_GROUP" => "root",
      "VOCAB_INDEX_FILE" => "vocabs.json",
      "VOCAB_LANGS" => [:en],
      "USING_ICA_ACTIVITIES" => false,
      "URI_HOST" => "w3id.solidarityeconomy.coop",
      "URI_PATH_PREFIX" => "ica-youth-network",
      "DEPLOYMENT_SERVER" => "sea-0-admin",
      "DEPLOYMENT_WEBROOT" => "/var/www/html/data1.solidarityeconomy.coop/",
      "VIRTUOSO_ROOT_DATA_DIR" => "/home/admin/Virtuoso/BulkLoading/Data/",
      "SPARQL_ENDPOINT" => "http://store1.solidarityeconomy.coop:8890/sparql",
      "VIRTUOSO_PASS_FILE" => "deployments/dev-0.solidarityeconomy.coop/virtuoso/dba.password",
      "SERVER_ALIAS" => "data1.solidarityeconomy.coop",
      "GEN_CSV_DIR" => caller_dir + "/generated-data/csv/",
      "WWW_DIR" => caller_dir + "/generated-data/www/",
      "GEN_DOC_DIR" => caller_dir + "/generated-data/www/doc/",
      "GEN_CSS_DIR" => caller_dir + "/generated-data/www/doc/css/",
      "GEN_VIRTUOSO_DIR" => caller_dir + "/generated-data/virtuoso/",
      "GEN_SPARQL_DIR" => caller_dir + "/generated-data/sparql/",
      "SPARQL_GET_ALL_FILE" => caller_dir + "/generated-data/sparql/query.rq",
      "SPARQL_LIST_GRAPHS_FILE" => caller_dir + "/generated-data/sparql/list-graphs.rq",
      "SPARQL_ENDPOINT_FILE" => caller_dir + "/generated-data/sparql/endpoint.txt",
      "SPARQL_GRAPH_NAME_FILE" => caller_dir + "/generated-data/sparql/default-graph-uri.txt",
      "GRAPH_NAME" => "https://w3id.solidarityeconomy.coop/ica-youth-network",
      "ONE_BIG_FILE_BASENAME" => caller_dir + "/generated-data/virtuoso/all",
      "SAME_AS_FILE" => "",
      "SAME_AS_HEADERS" => "",
      "DEPLOYMENT_DOC_SUBDIR" => "ica-youth-network",
      "DEPLOYMENT_DOC_DIR" => "/var/www/html/data1.solidarityeconomy.coop/ica-youth-network",
      "VIRTUOSO_NAMED_GRAPH_FILE" => caller_dir + "/generated-data/virtuoso/global.graph",
      "VIRTUOSO_SQL_SCRIPT" => "loaddata.sql",
      "VERSION" => "2020526214656",
      "VIRTUOSO_DATA_DIR" => "/home/admin/Virtuoso/BulkLoading/Data/2020526214656/",
      "VIRTUOSO_SCRIPT_LOCAL" => caller_dir + "/generated-data/virtuoso/loaddata.sql",
      "VIRTUOSO_SCRIPT_REMOTE" => "/home/admin/Virtuoso/BulkLoading/Data/2020526214656/loaddata.sql",
    }
    it "should generate an expected map" do
      value(config_map).must_equal expected_map
    end

    expected_listing = <<-HERE
/.
/csv
/sparql
/virtuoso
/www
/www/doc
/www/doc/css
HERE
    
    it "should create the expected directories" do
      value(listing).must_equal expected_listing
    end
  end

  describe "a valid config instance" do
    config_map = nil
    
    # TestConfig should recreate this + some contents
    FileUtils.rm_r generated_dir if File.exist? generated_dir

    # expansions relative to caller_dir, i.e. this script's dir
    config = TestConfig.new(caller_dir+"/config/valid.txt")

    # Make recursive directory listing here, before other tests delete it
    listing = Dir.glob(generated_dir+"/**/*", File::FNM_DOTMATCH)
                .map {|it| it.delete_prefix(generated_dir)+"\n" }
                .sort
                .join
    
    config_map = config.map
    
    #puts config_map
    expected_map = {
      "AUTO_LOAD_TRIPLETS" => true,
      "CSS_SRC_DIR" => caller_dir+"/css/",
      "SRC_CSV_DIR" => caller_dir+"/original-data/",
      "ORIGINAL_CSV" => "Youth-ledCoops.csv",
      "ORIGINAL_CSV_SCHEMA" => "schema.yml",
      "STANDARD_CSV" => caller_dir+"/generated-data/standard.csv",
      "TOP_OUTPUT_DIR" => caller_dir+"/generated-data/",
      "URI_SCHEME" => "https",
      "USE_ENV_PASSWORDS" => false,
      "ESSGLOBAL_URI" => "https://w3id.solidarityeconomy.coop/essglobal/V2a/",
      "DEPLOYMENT_WEB_USER" => "www-data",
      "DEPLOYMENT_WEB_GROUP" => "www-data",
      "VIRTUOSO_USER" => "root",
      "VIRTUOSO_GROUP" => "root",
      "VOCAB_INDEX_FILE" => "vocabs.json",
      "VOCAB_LANGS" => [:en],
      "USING_ICA_ACTIVITIES" => false,
      "MULTI_EQUAL" => "foo=bar=baz",
      "EMPTY_EQUAL" => "",
      "withLowercase0123456789" => "# this is not a comment #",
      "WITH_PADDING" => "with padding",
      "unique1" => "unique1",
      "SHARED" => "shared",
      "map" => "hello",
      "URI_HOST" => "w3id.solidarityeconomy.coop",
      "URI_PATH_PREFIX" => "ica-youth-network",
      "DEPLOYMENT_SERVER" => "sea-0-admin",
      "DEPLOYMENT_WEBROOT" => "/var/www/html/data1.solidarityeconomy.coop/",
      "DEPLOYMENT_RSYNC_FLAGS" => "--delete",
      "VIRTUOSO_ROOT_DATA_DIR" => "/home/admin/Virtuoso/BulkLoading/Data/",
      "SPARQL_ENDPOINT" => "http://store1.solidarityeconomy.coop:8890/sparql",
      "VIRTUOSO_PASS_FILE" => "deployments/dev-0.solidarityeconomy.coop/virtuoso/dba.password",
      "SERVER_ALIAS" => "data1.solidarityeconomy.coop",
      "TEST_INITIATIVE_IDENTIFIERS" => "16 40",
      "GEN_CSV_DIR" => caller_dir+"/generated-data/csv/",
      "WWW_DIR" => caller_dir+"/generated-data/www/",
      "GEN_DOC_DIR" => caller_dir+"/generated-data/www/doc/",
      "GEN_CSS_DIR" => caller_dir+"/generated-data/www/doc/css/",
      "GEN_VIRTUOSO_DIR" => caller_dir+"/generated-data/virtuoso/",
      "GEN_SPARQL_DIR" => caller_dir+"/generated-data/sparql/",
      "SPARQL_GET_ALL_FILE" => caller_dir+"/generated-data/sparql/query.rq",
      "SPARQL_LIST_GRAPHS_FILE" => caller_dir+"/generated-data/sparql/list-graphs.rq",
      "SPARQL_ENDPOINT_FILE" => caller_dir+"/generated-data/sparql/endpoint.txt",
      "SPARQL_GRAPH_NAME_FILE" => caller_dir+"/generated-data/sparql/default-graph-uri.txt",
      "GRAPH_NAME" => "https://w3id.solidarityeconomy.coop/ica-youth-network",
      "ONE_BIG_FILE_BASENAME" => caller_dir+"/generated-data/virtuoso/all",
      "SAME_AS_FILE" => "",
      "SAME_AS_HEADERS" => "",
      "DEPLOYMENT_DOC_SUBDIR" => "ica-youth-network",
      "DEPLOYMENT_DOC_DIR" => "/var/www/html/data1.solidarityeconomy.coop/ica-youth-network",
      "VIRTUOSO_NAMED_GRAPH_FILE" => caller_dir+"/generated-data/virtuoso/global.graph",
      "VIRTUOSO_SQL_SCRIPT" => "loaddata.sql",
      "VERSION" => "2020526214656",
      "VIRTUOSO_DATA_DIR" => "/home/admin/Virtuoso/BulkLoading/Data/2020526214656/",
      "VIRTUOSO_SCRIPT_LOCAL" => caller_dir+"/generated-data/virtuoso/loaddata.sql",
      "VIRTUOSO_SCRIPT_REMOTE" => "/home/admin/Virtuoso/BulkLoading/Data/2020526214656/loaddata.sql",
    }
    
    it "should generate an expected map" do
      value(config_map).must_equal expected_map
    end

    expected_listing = <<-HERE
/.
/csv
/sparql
/virtuoso
/www
/www/doc
/www/doc/css
HERE

    it "should create the expected directories" do
      value(listing).must_equal expected_listing
    end


    it "should respond to the keys as methods" do
      expected_map.each do |key, value|
        method = key.to_sym

        # Skip methods which are implemented on the class!
        if !config.class.method_defined? method
          value(config.send method).must_equal value
        end
      end
    end
    
    it "key methods should be singleton methods" do
      # create an instance with a unique2 key
      config2 = TestConfig.new(caller_dir+"/config/valid2.txt")

      # methods should be present on the correct instances
      value(config.unique1).must_equal 'unique1'
      value(config2.unique2).must_equal 'unique2'
      
      # but they shouldn't be present on the others
      value(config.respond_to? :unique2).must_equal false
      value(config2.respond_to? :unique1).must_equal false

      # common methods should return different values
      value(config.SHARED).must_equal 'shared'
      value(config2.SHARED).must_equal 'shared'
    end

    it "keys should not redefine existing methods" do
      # The map key for example should be allowed to exist in the config
      value(config.fetch 'map').must_equal 'hello'
      # But not clobber the :map method
      value(config.map).must_equal expected_map
    end
  end

  describe "a config instance with duplicates" do

    # TestConfig should recreate this + some contents
    FileUtils.rm_r generated_dir if File.exist? generated_dir

    it "should raise an exception" do
      err = value(proc do
        TestConfig.new(caller_dir+"/config/invalid-dupes.txt")
      end)
              .must_raise RuntimeError
      
      value(err.message).must_match "config key 'SOMETHING' duplicated on line 3"
    end
  end

  describe "a config instance with a invalid keys" do

    # TestConfig should recreate this + some contents
    FileUtils.rm_r generated_dir if File.exist? generated_dir

    it "(space) should raise an exception" do
      err = value(proc do
        TestConfig.new(caller_dir+"/config/invalid-keys-1.txt")
      end)
              .must_raise RuntimeError
      
      value(err.message).must_match "invalid config key 'SOMETHING ELSE' at line 2"
    end
    
    it "(colon) should raise an exception" do
      err = value(proc do
        TestConfig.new(caller_dir+"/config/invalid-keys-2.txt")
        end)
              .must_raise RuntimeError
      
      value(err.message).must_match "invalid config key 'SOMETHING:ELSE' at line 2"
    end
  end
  
  describe "a config instance with missing delimiters" do

    # TestConfig should recreate this + some contents
    FileUtils.rm_r generated_dir if File.exist? generated_dir

    it "should raise an exception" do
      err = value(proc do
        TestConfig.new(caller_dir+"/config/invalid-delims.txt")
      end)
              .must_raise RuntimeError
      
      value(err.message).must_match "config line with no '=' delimiter on line 2"
    end
  end
  # FIXME test missing mandatory values
  # also unknown values?
end
