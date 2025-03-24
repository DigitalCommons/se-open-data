# coding: utf-8
require "shellwords"
require "pathname"
require "se_open_data/utils/log_factory"
require "se_open_data/utils/deployment"
require "uri"
require "thor"
require "erb"

module SeOpenData
  # Defines the seod command cli interface, using Thor
  class Cli < Thor  
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default

    check_unknown_options!

    # enable exit_on_failure? feature
    def self.exit_on_failure?
      true
    end
    
    desc 'run_all', 'Run all the steps required to download and redeploy data.'
    long_desc <<DOCS
Runs the commands with  no parameters by default, or with params supplied
in an environment variable named for it, like `SEOD_<COMMAND>_PARAMS`, where
<COMMAND> is the upper-cased command name.

If any step fails to return success (if any are non-zero), it stops
and subsequent steps are not executed.

Returns true if all steps succeed, false if any fail.
DOCS
    def run_all
      %w(clean download convert generate deploy triplestore post_success).each do |name|
        params_var = "SEOD_#{name.upcase.gsub(/\s+/, '_')}_PARAMS" # shouldn't be spaces, but JIC..
        Log.info "Running command #{name} $#{params_var}"
        params = ENV[params_var].to_s.split
        Log.debug "Command params used for #{name}: #{params.inspect}"
        rc = self.class.start([name] + params)
        if rc != true and rc != 0 and rc != 100 # 100 means skipped, which is ok
          Log.error "stopping, #{name} failed"
          return false
        end
      end
      return true
    end

    desc 'clean', 'Removes all the generated files in the output directory'
    long_desc <<DOCS
This output directory is set by the {SeOpenData::Config} value `TOP_OUTPUT_DIR`
DOCS
    def clean
      config = load_config
      Log.info "Deleting #{config.TOP_OUTPUT_DIR} and any contents."
      FileUtils.rm_rf config.TOP_OUTPUT_DIR, secure: true
      return true
    end


    desc 'convert', 'Run the `converter` script to normalise the original data'
    long_desc <<DOCS
The script should be called `converter` and be in the current
directory. It must be present.

The script should read the file with a the name defined by
ORIGINAL_CSV from the directory defined by SRC_CSV_DIR.

The result should be written to the file name defined by STANDARD_CSV,
in the directory named by TOP_OUTPUT_DIR.
DOCS
    # Runs the `converter` script in the current directory, if present
    #
    # Note, although typically we expect the script to be written in
    # Ruby and use the SeOpenData library, we don't assume that and
    # invoke it as a separate process, to allow other languages and
    # tools to be used.
    #
    # The requirements are that:
    #
    # 1. Input data is read from a source, in whatever format, named
    #    in the configuration by the value of `ORIGINAL_CSV` in the
    #    directory, relative to the script's directory, named by
    #    `SRC_CSV_DIR`. (It doesn't actually have to be CSV format.)
    #
    # 2. Output data is written to the expected file, named by the
    #    configured value of `STANDARD_CSV`, in the directory named by
    #    `TOP_OUTPUT_DIR` (again relative to the script's directory).
    #    The file should be a CSV with the schema defined by
    #    {SeOpenData::CSV::Schemas::Latest}.
    #
    # The rest of the conversion process can then continue to
    # transform the data from here.
    #
    def convert
      return invoke_script("converter")
    end


    desc 'deploy [URI]', 'Deploys the generated data on a web server.'
    option :owner,
           desc: "set the deployed files' owner"
    option :group,
           desc: "set the deployed files' group"
    long_desc <<DOCS
Expects the generated data to have been created already by the
`generate` command, in the directory defined by the WWW_DIR configuration.

The destination path, and (optionally) host and ownership are defined
in the configuration, by DEPLOYMENT_SERVER, DEPLOYMENT_DOC_DIR,
DEPLOYMENT_WEB_USER and DEPLOYMENT_WEB_GROUP.

Before the deployment proceeds, the directory defined by
DEPLOYMENT_WEBROOT is checked for pre-existance.

If the --owner or --group options are supplied with an argument, this
defines the owner or group names set deployed files to. If this argument is
simply a period (e.g. '--owner .'), the current user or group is used. If
absent, values are taken from the configuration.
DOCS
    def deploy(uri = nil)
      config = load_config
      to_serv = config.respond_to?(:DEPLOYMENT_SERVER) ? config.DEPLOYMENT_SERVER : nil
      to_dir = config.DEPLOYMENT_DOC_DIR

      owner = case options[:owner]
              when nil then config.DEPLOYMENT_WEB_USER
              when '.' then nil # use current
              else options[:owner]
              end

      group = case options[:group]
              when nil then config.DEPLOYMENT_WEB_GROUP
              when '.' then nil # use current
              else options[:group]
              end

      if uri
        uri = URI(uri)
        case uri.scheme
        when 'rsync', 'file', nil
          to_serv = uri.host
          to_dir = File.join(uri.path, config.URI_PATH_PREFIX)
        else
          throw "unsupported uri scheme: #{uri.to_s}"
        end
      end

      deploy_files(
        to_server: to_serv,
        to_dir: to_dir,
        from_dir: config.GEN_DOC_DIR,
        ensure_present: config.DEPLOYMENT_WEBROOT,
        owner: owner,
        group: group,
      )
      return true
    end


    desc 'download', 'Runs the `downloader` script to get new data'
    long_desc <<DOCS
The script, if present, should be called `downloader` and be in the
current directory.

Does nothing if it is absent.

May require authentication credentials to be configured for the
download to be successful.
DOCS
    # Obtains new data by running the `downloader` script in the
    # current directory, if present
    #
    # Does nothing if absent.
    #
    # May require credentials to be configured.
    #
    # Note, although typically we expect the script to be written in
    # Ruby and use the SeOpenData library, we don't assume that and
    # invoke it as a separate process, to allow other languages and
    # tools to be used.
    #
    # The requirements are that:
    #
    # 1. Data is written, in whatever format, to the location named in
    #    the configuration by the value of `ORIGINAL_CSV` in the
    #    directory, relative to the script's directory, named by
    #    `SRC_CSV_DIR`. (It doesn't actually have to be CSV format.)
    #
    # This allows the `converter` script and the rest of the
    # conversion process can then continue to transform the data from
    # here.
    #
    # @return true on success, false on failure, or 100 (an
    # arbitrarily chosen code) to indicate there is no downloader
    # script, or that the script determinied there was nothing new to
    # download. This allows unnecessary rebuilds to be avoided.
    def download
      case invoke_script("downloader", allow_codes: 100, allow_absent: true, allow_failure: true)
      when true, nil then true
      when 100 then 100
      else false
      end
    end


    desc 'etag', 'Checks and updates the ETAG header recorded for the original data file'
    long_desc <<DOCS
Sends a HEAD request to the configured data source at DOWNLOAD_URL,
and stores the ETAG header in a file adjacent to it, but with the
.etag suffix, for comparison with future download attempts.
DOCS
    def etag
      # Find the config file...
      config = load_config

      # Download the data
      Log.info etag(config.DOWNLOAD_URL)
      return true
    end


    desc 'generate', 'Generates the static data in `WWW_DIR` and `GEN_SPARQL_DIR`'
    long_desc <<DOCS
Expects normalised data to have been generated by the `convert`
command, as described in the documentation for that method.

Transforms this into (typically but not necessarily) static linked
open data files for publishing, along with the normalised CSV file and
some other metadata. This is then ready to be deployed on a web server.

See the API documentation for {generate} for more details of the output
files.
DOCS
    # Generates the static data in `WWW_DIR` and `GEN_SPARQL_DIR`
    #
    # Expects data to have been generated by {convert},
    # as described in the documentation for that method.
    #
    # The static data consists of:
    #
    # - *WWW_DIR*`/doc/`*STANDARD_CSV* - the CSV file generated by the convert step
    # - *WWW_DIR*`/doc/` - one .html, .rdf and .ttl file for each
    #   initiative, named after the initiative's identifier field.
    # - *WWW_DIR*`/doc/` - also, a copy of any files found in *TOP_OUTPUT_DIR*`/extras`
    # - *WWW_DIR*`/doc/meta.json` - some information about the data source and generation process
    # - *GEN_SPARQL_DIR*`/` - the following files at least:
    #   - `default-graph-uri.txt` - containing the linked-data graph's
    #     default URI
    #   - `endpoint.txt` - containing the URL of a SPARQL end-point
    #     which can be used to query the graph
    #   - `query.rq` - containing a SPARQL query which can be passed to
    #     this end-point that returns a complete list of initiatives
    #
    # Other .rq query files may exist, depending on the application.
    #
    # FIXME what defines the requirements of the data generated by the query?
    def generate
      require 'se_open_data/vocab_to_index'
      require "json"
      require "etc"
      require "socket"
      config = load_config

      # Delete and re-create an empty WWW_DIR directory.  It's
      # important to start from scratch, to avoid incompletely
      # reflecting config changes (which would happen if we tried to
      # regenerate only those missing files). We don't really want to
      # check timestamps like Make does, because that gets a bit
      # complicated, ignores changes not reflected in the filesystem,
      # e.g. dates, and can't spot spurious junk left in the directory
      # by manual copies etc.
      Log.info "recreating #{config.WWW_DIR}"
      FileUtils.rm_rf config.WWW_DIR, secure: true
      FileUtils.mkdir_p config.GEN_DOC_DIR # need this subdir
      
      FileUtils.rm_rf config.GEN_SPARQL_DIR, secure: true
      

      case invoke_script("generator", allow_absent: true)
      when nil
        # Default generate behaviour, if there is no generator script
        generate_vocab_index
        generate_rdf
      end

      # Copy original CSV into upload folder
      standard_csv = File.join(config.GEN_DOC_DIR, 'standard.csv')
      FileUtils.cp config.STANDARD_CSV, standard_csv

      # Copy any files from the "extras" dir into GEN_DOC_DIR
      # (Note, trailing '.' makes cp_r copy contents of extras_dir, not dir itself)
      extras_dir = File.join(config.TOP_OUTPUT_DIR, 'extras', '.')
      if File.exist? extras_dir
        FileUtils.cp_r extras_dir, config.GEN_DOC_DIR
      end

      # Write timestamp and hash metadata. This is so we can see where
      # and how the data was generated.
      # Note, meta.json absent at this point so is not included in doc_hash
      commit_id = `git rev-parse HEAD 2>/dev/null`.chomp
      commit_id += "-modified" if system('git diff-index --quiet HEAD')
      standard_data_hash = `git hash-object #{config.STANDARD_CSV}`.chomp
      doc_hash = `cd #{config.GEN_DOC_DIR} && find . | git hash-object --stdin`.chomp
      metadata = {
        timestamp: Time.now.getutc,
        commit_id: commit_id,
        standard_data_hash: standard_data_hash,
        doc_hash: doc_hash,
        user: Etc.getlogin,
        host: Socket.gethostname,
      }
      meta_json = File.join(config.GEN_DOC_DIR, 'meta.json')
      IO.write meta_json, metadata.to_json
      return true
    end


    desc 'generate_digest_index', 'Scan the STANDARD_CSV file and generate a DIGEST_INDEX file'
    long_desc <<DOCS
DIGEST_INDEX is a tab-delimited file with two columns: "Key" and
"Digest".  It represents the state each row, indicated by the
key, with a digest, allowing changes to be inferred generically.
DOCS
    # Scan the STANDARD_CSV and generate a DIGEST_INDEX
    #
    # DIGEST_INDEX is a tab-delimited file with two columns: "Key" and
    # "Digest".  It represents the state each row, indicated by the
    # key, with a digest, allowing changes to be inferred generically.
    #
    # This information is intended to allow differential updates to
    # downstream consumers of the data. The specific case in mind is a
    # Murmurations index server, which has rate limiting which could
    # limit the amount of data registered, and prefers to be notified
    # only of changes (additions, deletions, and alterations).
    #
    # A digest index is read, manipulated and saved using the class
    # SeOpenData::Utils::DigestIndex.  More details of the file format
    # can be found there.
    #
    # DIGEST_INDEX and STANDARD_CSV are names of files (with no path)
    # defined in the config. Their locations are, respectively, within
    # GEN_DOC_DIR and TOP_OUTPUT_DIR.
    #
    # This returns true on success (actually, the number of non-header
    # rows in the DIGEST_INDEX, which should equal the number of
    # non-header rows in STANDARD_CSV)
    def generate_digest_index
      require 'se_open_data/utils/digest_index'
      
      config = load_config
      digest_file = config.fetch('DIGEST_INDEX', 'digest.tsv')
      
      FileUtils.mkdir_p config.GEN_DOC_DIR # need this subdir
      digest_path = File.join(config.GEN_DOC_DIR, digest_file)

      digest_index = SeOpenData::Utils::DigestIndex.new
      digest_index
        .load_csv(config.STANDARD_CSV, key_fields: ['Identifier']) # FIXME
        .save(digest_path)

      return digest_index.index.size
    end


    desc 'generate_murmurations_profiles', ''
    def generate_murmurations_profiles
      require "se_open_data/murmurations"
      require "csv"
      config = load_config
      FileUtils.mkdir_p config.GEN_DOC_DIR # need this subdir
      
      # Convert CSV into Murmurations data structures
      ::CSV.foreach(config.STANDARD_CSV, headers:true) do |row|
        next if row.header_row?

        output_file = File.join(config.GEN_DOC_DIR, "#{row['Identifier']}.murm.json")
        SeOpenData::Murmurations.write(config.GRAPH_NAME, row.to_h, output_file)
      end
      
      return true
    end


    desc 'generate_rdf', 'Generate the RDF data'
    long_desc <<DOCS
These are Turtle, XML/RDF and HTML files, one per initiative.
They all contain approximately the same data in a different
form. The HTML embeds the TTL, CSV and XML formats in a form
which can be displayed in a browser.

The files are written into the directory set by
config.GEN_DOC_DIR, and with a name set by the initiative
Identifier field, and a suffix indicating the type.
DOCS
    # Generate the RDF data
    #
    # These are Turtle, XML/RDF and HTML files, one per initiative.
    # They all contain approximately the same data in a different
    # form. The HTML embeds the TTL, CSV and XML formats in a form
    # which can be displayed in a browser.
    #
    # The files are written into the directory set by
    # config.GEN_DOC_DIR, and with a name set by the initiative
    # Identifier field, and a suffix indicating the type.
    def generate_rdf
      require "se_open_data/initiative/rdf"
      require "se_open_data/initiative/collection"
      require "se_open_data/csv/standard"

      config = load_config
      Log.info "recreating #{config.GEN_SPARQL_DIR}"
      FileUtils.mkdir_p config.GEN_SPARQL_DIR
      
      IO.write config.SPARQL_ENDPOINT_FILE, config.SPARQL_ENDPOINT + "\n"
      IO.write config.SPARQL_GRAPH_NAME_FILE, config.GRAPH_NAME + "\n"

      # Copy contents of CSS_SRC_DIR into GEN_CSS_DIR
      FileUtils.cp_r File.join(config.CSS_SRC_DIR, "."), config.GEN_CSS_DIR

      # Find the relative path from GEN_DOC_DIR to GEN_CSS_DIR
      doc_dir = Pathname.new(config.GEN_DOC_DIR)
      css_dir = Pathname.new(config.GEN_CSS_DIR)
      css_rel_dir = css_dir.relative_path_from doc_dir

      # Enumerate the CSS files there, relative to GEN_DOC_DIR
      css_files = Dir.glob(css_rel_dir + "**/*.css", base: config.GEN_DOC_DIR)
      
      rdf_config = SeOpenData::Initiative::RDF::Config.new(
        config.GRAPH_NAME,
        config.ESSGLOBAL_URI,
        config.ONE_BIG_FILE_BASENAME,
        config.SPARQL_GET_ALL_FILE,
        css_files,
        nil, #    postcodeunit_cache?
        SeOpenData::CSV::Standard::V1,
        config.SAME_AS_FILE == "" ? nil : config.SAME_AS_FILE,
        config.SAME_AS_HEADERS == "" ? nil : config.SAME_AS_HEADERS,
        config.USING_ICA_ACTIVITIES
      )

      # Load CSV into data structures, for this particular standard
      File.open(config.STANDARD_CSV) do |input|
        input.set_encoding(Encoding::UTF_8)

        collection = SeOpenData::Initiative::Collection.new(rdf_config)
        collection.add_from_csv(input.read)
        collection.serialize_everything(config.GEN_DOC_DIR)
      end

      return true
    end


    desc 'generate_vocab_index', 'Generates a vocab index file'
    long_desc <<DOCS
This vocab index is a JSON file containing a look-up table of
abbreviated SKOS vocab URIs to human-language labels in various
languages, defined by the config, and obtained from one or more
SKOS vocab files. It can be used by mykomap to define
vocabularies AKA taxonomies used in the data.

The name is defined by VOCAB_INDEX_FILE, and it is written to GEN_DOC_DIR.
DOCS
    # Generate a vocab index
    #
    # This index is a JSON file containing a look-up table of
    # abbreviated SKOS vocab URIs to human-language labels in various
    # languages, defined by the config, and obtained from one or more
    # SKOS vocab files. It can be used by mykomap to define
    # vocabularies AKA taxonomies used in the data.
    #
    # The file written into the directory set by config.GEN_DOC_DIR,
    # and with a name set by config.VOCAB_INDEX_FILE. The former is
    # generated if not present.
    def generate_vocab_index
      require 'se_open_data/vocab_to_index'
      require 'linkeddata'
      config = load_config
      FileUtils.mkdir_p config.GEN_DOC_DIR # need this subdir
      
      vocab_uris = config.map.collect do |key, value|
        if key.start_with? 'VOCAB_URI_'
          prefix = key[10..].downcase
          [value, prefix]
        end
      end.compact.to_h
      
      graph = ::RDF::Graph.new
      vocab_uris.each do |uri, prefix|
        uri = uri.sub(%r{/+$}, '') # remove the trailing slash, or we don't get the .ttl file
        Log.debug "loading vocab #{prefix}: from #{uri}"
        graph << ::RDF::Graph.load(uri, headers: {'Accept' => 'text/turtle'})
      end
      
      vocab_indexer = SeOpenData::VocabToIndex.new(graph.to_enum)
      vocab_index = vocab_indexer.aggregate({
                                              languages: config.VOCAB_LANGS,
                                              vocabularies: [
                                                { uris: vocab_uris }
                                              ],
                                            })
      vocab_index_file = File.join(config.GEN_DOC_DIR, config.VOCAB_INDEX_FILE)
      Log.debug "writing vocab index file #{vocab_index_file}"
      IO.write vocab_index_file, JSON.generate(vocab_index)

      return true
    end


    desc 'http_download', 'Obtains new data from an HTTP URL'
    long_desc <<DOCS
The URL is defined by the configuration option DOWNLOAD_URL, and it is
written to the directory defined by SRC_CSV_DIR

Returns true on success, 100 if there is no new data, or false on
failure.
DOCS
    # Obtains new data from an HTTP URL
    #
    # This method is designed to offer one implementation for the
    # `downloader` script invoked by the (more generic)
    # {#download} method. So to utilise it, typically the
    # executable `downloader` Ruby script in the data project
    # directory would contain something like this:
    #
    #     #!/usr/bin/env ruby
    #     # coding: utf-8
    #     require_relative '../tools/se_open_data/lib/load_path'
    #     require 'se_open_data/cli'
    #     
    #     # Run the entry point which downloads the data if we're
    #     # invoked as a script.  But also exit with the returned
    #     # value, to signal whether it succeeded (return code 0 or
    #     # true), failed (1 or false), or was just skipped because
    #     # there is no new data (return code 100)
    #     
    #     exit SeOpenData::Cli.http_download if __FILE__ == $0
    #
    # Then the source of the data would be configured using one of the
    # standard config files (`default.conf`, `local.conf` etc., @see
    # {SeOpenData::Config}), using the `DOWNLOAD_URL` attribute.
    # For example:
    #
    #     DOWNLOAD_URL = https://example.com/original.csv
    #
    # This then minimises the amount of duplication in each project,
    # whilst still allowing projects do customise the exact operation
    # of this step when that is needed.
    #
    # The step can be invoked directly like this:
    #
    #     ./downloader
    #
    # As well as via the {SeOpenData} library's command-line API
    # {SeOpenData::Cli}:
    #
    #     seod download
    #
    # To run all the steps,
    # @see #run_all
    #
    # The method works as follows. The HTTP ETAG code is saved in a
    # file named after the original csv, but with an `.etag` extension
    # appended. If this ETAG file exists, this method checks if this
    # has changed before downloading again, and returns 100 if it
    # hasn't changed.
    #
    # (Obviously this requires that the remote web server supplies the
    # ETAG header, and does it correctly.)
    #
    # @return true on success, 100 if there is no new data, or false
    # on failure.
    def http_download
      # Find the config file...
      config = load_config

      # Make the target directory if needed
      FileUtils.mkdir_p config.SRC_CSV_DIR

      # Original src csv file
      original_csv = File.join(config.SRC_CSV_DIR, config.ORIGINAL_CSV)

      # ETAG file store
      etag_file = original_csv+'.etag'
      etag = etag(config.DOWNLOAD_URL)
      
      if File.exist? etag_file
        # Check if we should inhibit another download
        # Note, an empty etag means there is no etag, so we should
        # not inhibit the download in that case.
        old_etag = IO.read(etag_file).strip
        if old_etag != '' and old_etag == etag
          Log.warn "No new data"
          return 100
        end
      end
      
      # Download the data
      IO.write etag_file, etag
      IO.write original_csv, fetch(config.DOWNLOAD_URL)
      return true
    end


    desc 'limesurvey_export', 'Obtains new data from limesurvey.'
    long_desc <<DOCS
The downloads CSV data from the Lime Survey API.

Relevant configuration values are:
- `LIMESURVEY_SERVICE_URL` - the URL of the LimeSurvey API endpoint
- `LIMESURVEY_SURVEY_ID` - the ID of the survey to download
- `LIMESURVEY_USER` - the user name to authenticate with
- `LIMESURVEY_PASSWORD_PATH` - a path to give to `pass` command
   which will decrypt the password to authenticate with.

Returns true on success, 100 if there is no new data, or false
on failure.  Although currently there is no way to detect when
data has changed, so this method never returns 100.
DOCS
    # Obtains new data from limesurvey.
    #
    # This method is designed to offer one implementation for the
    # `downloader` script invoked by the (more generic)
    # {#download} method. So to utilise it, typically the
    # executable `downloader` Ruby script in the data project
    # directory would contain something like this:
    #
    #     #!/usr/bin/env ruby
    #     # coding: utf-8
    #     require_relative '../tools/se_open_data/lib/load_path'
    #     require 'se_open_data/cli'
    #     
    #     # Run the entry point which downloads the data if we're
    #     # invoked as a script.  But also exit with the returned
    #     # value, to signal whether it succeeded (return code 0 or
    #     # true), failed (1 or false), or was just skipped because
    #     # there is no new data (return code 100)
    #     
    #     exit SeOpenData::Cli.limesurvey_export if __FILE__ == $0
    #
    # Then the source of the data would be configured using one of the
    # standard config files (`default.conf`, `local.conf` etc., @see
    # {SeOpenData::Config}), using the following attributes:
    #
    # - `LIMESURVEY_SERVICE_URL` - the URL of the LimeSurvey API endpoint
    # - `LIMESURVEY_SURVEY_ID` - the ID of the survey to download
    # - `LIMESURVEY_USER` - the user name to authenticate with
    # - `LIMESURVEY_PASSWORD_PATH` - a path to give to `pass` command
    #    which will decrypt the password to authenticate with.
    #
    # e.g.:
    #
    #     LIMESURVEY_SERVICE_URL = https://solidarityeconomyassociation.limequery.com/index.php/admin/remotecontrol
    #     LIMESURVEY_USER = Nick
    #     LIMESURVEY_PASSWORD_PATH = people/nick/lime-survey.password 
    #     LIMESURVEY_SURVEY_ID = 899558
    #
    # This then minimises the amount of duplication in each project,
    # whilst still allowing projects do customise the exact operation
    # of this step when that is needed.
    #
    # The step can be invoked directly like this:
    #
    #     ./downloader
    #
    # As well as via the {SeOpenData} library's command-line API
    # {SeOpenData::Cli}:
    #
    #     seod download
    #
    # To run all the steps,
    # @see #run_all
    #
    # The method works by downloading the data from the Lime Survey API.
    # @see SeOpenData::LimeSurveyExporter
    #
    # @return true on success, 100 if there is no new data, or false
    # on failure.  Although currently there is no way to detect when
    # data has changed, so this method never returns 100.
    def limesurvey_export
      require "se_open_data/lime_survey_exporter"
      require "se_open_data/utils/password_store"

      config = load_config

      FileUtils.mkdir_p config.SRC_CSV_DIR
      src_file = File.join config.SRC_CSV_DIR, config.ORIGINAL_CSV

      pass = SeOpenData::Utils::PasswordStore.new(use_env_vars: config.USE_ENV_PASSWORDS)
      Log.debug "Checking ENV for passwords" if pass.use_env_vars?
      password = pass.get config.LIMESURVEY_PASSWORD_PATH

      SeOpenData::LimeSurveyExporter.session(
        config.LIMESURVEY_SERVICE_URL,
        config.LIMESURVEY_USER,
        password
      ) do |exporter|
        IO.write src_file, exporter.export_responses(config.LIMESURVEY_SURVEY_ID, "csv", "en")
      end
      return true
    end


    desc 'murmurations_registration', 'Register published initiatives on a Murmurations index.'
    long_desc <<DOCS
Attempts to register or remove initiatives published via the `deploy`
command with the configured murmurations index server.

Murmurations is a decentralised protocol for the publishing and
discovery of resources.

The data should have been previously published using the `deploy`
command.

Returns false on outright failure, or an integer value on (partial)
success, indicating the number of failed registrations/removals. Zero
is complete success, and any other number indicates partial success.
DOCS
    # Attempts to register or remove initiatives published in a web
    # directory with the configured murmurations index server.
    #
    # To emphasise: this works with remote data, and should be invoked
    # after the data has been deployed.
    #
    # It assumes that:
    # - config.DIGEST_INDEX is the name of a digest index file
    # - hosted on the web in the directory given by the GRAPH_NAME URI,
    # - the Murmerations profiles are hosted in the same directory
    # - for every key in the index (which shold be URL-safe), there
    #   is a profile named "<key>.murm.json"
    # - the digests in the index represent the content of these profiles,
    #   in that if the digest changes, the content has changed.
    # - if the digest is are blank, the file will be unconditionally updated
    #   (because it will never match a digest)
    #
    # The previous state of the profiles is obtained from a cached
    # digest index stored at a path given by
    # config.DIGEST_INDEX_CACHE.
    #
    # The new digest is downloaded and compared with the cached one.
    # The differences is used to determine whether to register a
    # profile if it is new or has changed, or remove a profile if has
    # gone.
    #
    # @return false on outright failure, or an integer value on
    # (partial) success, indicating the number of failed
    # registrations/removals. Zero is complete success, and any other
    # number indicates partial success.
    def murmurations_registration
      require "csv"
      require "se_open_data/murmurations"
      require "se_open_data/utils/digest_index"
      config = load_config
      
      index_url = config.fetch('MURMURATIONS_INDEX_URL', 'https://test-index.murmurations.network/v2')


      new_digest_index = SeOpenData::Utils::DigestIndex.new
      new_digest_index_file = config.fetch('DIGEST_INDEX', 'digest.tsv')
      unless new_digest_index_file
        Log.error "Digest index location not configured with DIGEST_INDEX, "+
                  "not registering murmurations profiles"
        return false
      end

      # Use a HEAD query to get the actual URL the digest index
      # resides at.  Starting from here, typically a Permanent URL
      # which redirects to the actual URL
      base_publish_url = config.GRAPH_NAME 
      new_digest_index_url = File.join(base_publish_url, new_digest_index_file)
      
      response = head new_digest_index_url # Follows redirects

      resolved_new_digest_index_url = 
        if response.code == '200'
          response.uri.to_s
        else
          Log.error "failed to load digest index from #{new_digest_index_url}: "+
                    "#{response.message}"
          Log.debug "response body: #{response.body}"
          return false
        end

      # And from that URL derive the base URL below which we assume
      # all profiles are published.
      resolved_base_publish_url = File.dirname(resolved_new_digest_index_url)

      # Now download the digest index and parse it.
      new_digest_index.parse_str(fetch resolved_new_digest_index_url)

      # Load the old digest index from the local cache - if present
      old_digest_index_file = config.DIGEST_INDEX_CACHE
      old_digest_index = SeOpenData::Utils::DigestIndex.new
      if File.exist? old_digest_index_file
        old_digest_index.load(old_digest_index_file)
      else 
        Log.warn "No cached digest index found at #{old_digest_index_file}, "+
                 "can only register all current murmurations profiles"
      end

      # Compare the old and new digest indexes and use that to mark
      # profiles for update or removal
      update = []
      remove = []
      keys = {}
      old_digest_index.compare(new_digest_index) do |key, old_index, new_index|
        if old_index != new_index
          url = File.join(resolved_base_publish_url, key + '.murm.json')
          keys[url] = key
          
          if new_index == nil
            remove << url
          else
            update << url
          end
        end
      end

      # Perform the update/removals. Any failures will need to be
      # noted.
      statuses = SeOpenData::Murmurations.new(
        base_publish_url: resolved_base_publish_url,
        index_url: index_url,
      ).register(
        update_urls: update,
        remove_urls: remove,
      )

      # If any registrations fail to update or remove, this means
      # their cached digest index entry should be such that their
      # state is always updated/removed next time. We do that by
      # inserting an empty value, which is not "absent" but will
      # never match a new digest
      failures = statuses.to_a
                   .filter { |item| item[1] == false }
                   .collect { |item| keys[item[0]] }
      new_digest_index.invalidate(*failures)

      # Save the digest index
      new_digest_index.save(old_digest_index_file)

      return failures.size # A truthy value, indicating the number of failures
    end


    desc 'post_success', 'Runs a `post_success` script in the current directory, if present.'
    long_desc <<DOCS
The `post_success` script's purpose is to allow arbitrary
post-success operations to be added, such as notifications to
other systems.  It should only be run after successful
completion, and not if any step failed.

Note, although typically we expect the script to be written in
Ruby and use the SeOpenData library, we don't assume that and
invoke it as a separate process, to allow other languages and
tools to be used.

Returns true on success, false if there was failure, nil to
indicate there is no `post_success` script.
DOCS
    # Runs the `post_success` script in the current directory, if present.
    #
    # The post_success script's purpose is to allow arbitrary
    # post-success operations to be added, such as notifications to
    # other systems.  It should only be run after successful
    # completion, and not if any step failed.
    #
    # Note, although typically we expect the script to be written in
    # Ruby and use the SeOpenData library, we don't assume that and
    # invoke it as a separate process, to allow other languages and
    # tools to be used.
    #
    # @return true on success, false if there was failure, nil to
    # indicate there is no post_success script.
    def post_success
      case invoke_script("post_success", allow_absent: true, allow_failure: true)
      when true, nil then true
      else false
      end
    end

    
    desc 'triplestore', 'Bulk-imports the linked-data graph to a Virtuoso triplestore server.'
    option :from,
           lazy_default: :unset,
           desc: "Sets the local folder from which files are sourced for the import."
    option :datafiles,
           type: :hash,
           lazy_default: {},
           desc: "Sets the list of supplementary files to download into the source directory."
    option :base_published_url,
           lazy_default: :unset,
           desc: "Sets the base URI to prepend to supplementary files' source URLs, where relative,"    

    option :via,
           lazy_default: :unset,
           default: :default,
           desc: "Sets (or disable) the path (local or an rsync:// URL) to copy data to before attempting an import."
    option :require_via_dir,
           lazy_default: :unset,
           type: :numeric,
           desc: "Sets the number of components of the target path which must exist before uploading."
    option :remove_via_dir,
           lazy_default: :unset,
           type: :boolean,
           desc: "If true, remove the target path after the process."
    option :owner,
           lazy_default: :unset,
           desc: "Sets the intermediate destination files' owner."
    option :group,
           lazy_default: :unset,
           desc: "Sets the intermediate destination files' group."
    
    option :auto_load_triplets,
           lazy_default: :unset,
           type: :boolean,
           desc: "If true (the default), bulk-import the data."
    option :graph_uri,
           lazy_default: :unset,
           desc: "Sets the graph URI to import the data into."
    option :pattern,
           lazy_default: :unset,
           desc: "Sets which data filenames to import, using SQL 'like' pattern. Defaults to '*.rdf'."
    option :password_id,
           lazy_default: :unset,
           desc: "Sets the identifier given the to password store to get the Virtuoso password."
    option :dbuser,
           lazy_default: :unset,
           desc: "Sets the user to log into the Virtuoso database as when importing. Defaults to 'dba'"
    option :password_from_env,
           lazy_default: :unset,
           desc: "Tell the password store module to use environment variable instead of `pass`"

    long_desc <<DOCS
Expects triples data files to have been generated already by the
`generate` command, in a format that Virtuoso can import (typically
TTL, RDF, or N3).

By default some supplemental files are downloaded from the web into
the same folder, and this requires the folder to be writable. However,
this can be changed or disabled via the --datafiles option.

The no-parameters version of this command gets all of its options from
the configuration file, which sets an intermediate destination of the
data files on the local or a remote server, from which the bulk-import
is performed.

The CLI parameters will override or alter the file-based
configuration.

The CLI parameter `--via` allows the intermediate destination to be
altered or disabled (using `--no-via`), which means that the data can
be imported directly from the source directory (if the virtuoso server
is local and is configured to permit this with the `DirsAllowed`
parameter in `virtuoso.ini`.

Whether or not this intermediate directory needs to pre-exist or is
created if absent is controlled by `--require_via_dir`. Whether it is
deleted before the command exits is controlled by `--remove_via_dir`.

It is also possible to disable the bulk import step using
`--auto_load_triplets false`, which means that nothing is done but
(optionally) download supplemental datafiles and deploy the resulting
collection to the "intermediate" destination (which is therefore
effectively the final destination).

Otherwise, a password for the virtuoso server needs to be obtained,
and the passwords store command `pass` is used for this by default. A
`--password_id` option can override the default path configured to
give `pass`.  The `--passwords_from_env` option can be set to switch
to getting the password from an environment variable named
`PASSWORD__<id>` where `<id>` is a symbolic representation of the
password id: alphabetic characters are upper-cased, and sequences of
non-numeric characters are converted to an underscore.

DOCS
    # Uploads the linked-data graph to the Virtuoso triplestore server
    #
    # Aims to support a number of old and newer scenarios. The older cases
    # were completely configuration based, but were inflexible in the case
    # where deployment needed to fit with the host environment, in particular
    # when the process was running as a normal user rather than a user with
    # special privileges to write to directories owned by the webserver or the
    # virtuoso database. 
    #
    # - Legacy cases, with no command-line arguments. Deploy is performed
    #   as per the config file.
    #   - Scenario 1: import to remote virtuoso server via remote bulk-imported copy
    #     Requires DBA user password, ssh (+ probably root) access
    #   - Scenario 2: import to local virtuoso server via bulk-imported copy
    #     Requires DBA user password, root access
    # - Newer scenarios supported with command-line arguments
    #   - Scenario 3: import via custom location on remote server
    #     Requires DBA user password, ssh and write access to destination folder only
    #   - Scenario 3: import via custom location on local server
    #     Requires DBA user password, and write access to destination folder only
    #   - Scenario 4: import directly from source location on local server
    #     Requires DBA user password, and (optionally) write access to source folder only
    #   - Scenario 5: simply deploy files to a destination location on local or
    #     remote server.  Requires write access to source folder only, optionally ssh access.
    #
    # All parameters taken from config, but usual behaviour is to
    # bulk-upload locally/remotely via a temp dir below a configured base path.
    # Password required.
    #
    # Scenario 2: custom bulk upload using configured base path
    #
    # As above but some values overridden
    #
    # Scenario 3: bulk upload directly from from_dir
    #
    # No copy then required.
    #
    # Scenario 4: no bulk upload
    #
    # This step just not performed

    def triplestore
      require 'ostruct'
      #abort options.inspect

      px = OpenStruct.new
      # Parameters for source data
      px.from_dir = :unset
      px.datafiles = :unset
      px.base_published_url = :unset

      # Parameters for any intermediate destination
      px.via_host = :unset
      px.via_dir = :unset
      px.ensure_via_dir = :unset
      px.remove_via_dir = :unset
      px.via_owner = :unset
      px.via_group = :unset

      # Parameters for the triplestore import
      px.auto_load_triplets = :unset
      px.graph_uri = :unset
      px.pattern = :unset
      px.password_id = :unset
      px.dbuser = :unset
      px.password_from_env = :unset

      # Gather the config values and resolve the options and
      # parameters above against it.
      begin
        config = load_config

        begin # Parameters for the source data
          px.from_dir = _opt :from, config.GEN_VIRTUOSO_DIR
          px.base_published_url = _opt :base_published_url, config.ESSGLOBAL_URI
          
          px.datafiles = _opt :datafiles, {
                                # legacy defaults
                                "vocab/" => "essglobal_vocab.rdf",
                                "standard/organisational-structure" => "organisational-structure.rdf",
                                "standard/activities" => "activities.rdf",
                                "standard/activities-ica" => "activities-ica.rdf",
                                "standard/activities-modified" => "activities-modified.rdf",
                                "standard/base-membership-type" => "base-membership-type.rdf",
                                "standard/qualifiers" => "qualifiers.rdf",
                                "standard/countries-iso" => "countries-iso.rdf",
                                "standard/regions-ica" => "regions-ica.rdf",
                                "standard/super-regions-ica" => "super-regions-ica.rdf",
                              }
        end
        
        begin # Parameters for the (optional) intermediate destination
          
          # Set via_host via_dir, and ensure_via_dir depending on whether
          # via is set (implying the equivalent parameter passed)
          case options[:via]
          when nil # --no-via (no parameters supported)
            # Don't use an intermediate destination
            px.via_host = nil
            px.via_dir = nil
            px.ensure_via_dir = nil
            px.remove_via_dir = nil
          when :default, :unset # --via with no parameter, or no --via present
            # legacy defaults
            px.via_host = config.respond_to?(:VIRTUOSO_SERVER) ? config.VIRTUOSO_SERVER : nil
            px.via_dir = config.VIRTUOSO_DATA_DIR if px.via_dir == :unset

            px.ensure_via_dir =
              case options[:require_via_dir]
              when nil, :unset
                config.VIRTUOSO_ROOT_DATA_DIR # legacy default
              else
                truncate_path(px.via_dir, options[:require_via_dir])
              end
            
            px.remove_via_dir = _opt :remove_via_dir, true # legacy default
            
          else # A parameter passed, parse it
            uri = URI(options[:via])

            # Validate the scheme
            case uri.scheme
            when 'rsync', 'file', nil
            else
              throw "unsupported uri scheme: #{uri.to_s}"
            end
            
            px.via_host = uri.host
            px.via_dir = uri.path
            require_via_dir = _opt :require_via_dir
            px.ensure_via_dir = truncate_path(px.via_dir, require_via_dir)
            px.remove_via_dir = _opt :remove_via_dir, false
          end
          
          px.via_owner = case options[:owner]
                         when nil, :unset then config.VIRTUOSO_USER # legacy default
                         when '.' then nil # use current user
                         else options[:owner]
                         end
          px.via_group = case options[:group]
                         when nil, :unset then config.VIRTUOSO_GROUP # legacy default
                         when '.' then nil # use current group
                         else options[:group]
                         end
        end
        
        begin # Parameters for the import process
          px.auto_load_triplets = _opt :auto_load_triplets, config.AUTO_LOAD_TRIPLETS
          px.graph_uri = _opt :graph_uri, config.GRAPH_NAME
          px.pattern = _opt :pattern, '*' # legacy default
          px.password_id = _opt :password_id, config.VIRTUOSO_PASS_FILE
          px.dbuser = _opt :dbuser, 'dba'
          px.password_from_env = _opt :password_from_env, config.USE_ENV_PASSWORDS 
        end
      end

      # Make sanity checks
      #abort px.inspect
      px.each_pair do |name, val|
        if val == :unset
          raise "implementation error, configuration incomplete:\n"+px.inspect
        end
      end
      
      # Download the required remote datafiles into from_dir
      fetch_many dest_path: px.from_dir, items: px.datafiles, base_url: px.base_published_url

      begin
        if px.via_dir
          deploy_files(
            to_server: px.via_host, # only set if rsync:
            to_dir: px.via_dir,
            from_dir: px.from_dir,
            ensure_present: px.ensure_via_dir,
            owner: px.via_owner,
            group: px.via_group,
          )
        end
        
        if px.auto_load_triplets
          require "se_open_data/utils/password_store"      
          
          # This gets the database password from the encrypted password store, or
          # from the environment
          pass = SeOpenData::Utils::PasswordStore.new(use_env_vars: px.password_from_env)
          Log.debug "Checking ENV for passwords" if px.password_from_env      
          password = pass.get px.password_id
          
          # Attempt to bulk import the deployed triplets
          
          rc, output = bulk_import(
                remote_host: px.via_host,
                directory: px.via_dir || px.from_dir,
                graph_uri: px.graph_uri,
                pattern: px.pattern,
                password: password,
                user: px.dbuser,
                raise_on_error: true
              )
          return rc
        end

      ensure # even on errors
        
        if px.via_dir && px.remove_via_dir
          # remove the directory
          if px.via_host
            cmd = ['ssh', '-T', px.via_host, 'rm', '-rvf', px.via_dir]
            Log.info cmd.inspect
            system! *cmd
          else
            Log.info FileUtils.rm_r(px.via_dir, secure: true, verbose: true)
          end
        end
      end
      
    end

    # Shim for legacy usages of class command_* and other methods
    def self.method_missing(message, *args, **kwargs, &block)
      # Deal with command_methods which are now truncated and instance methods
      if message.start_with? 'command_'
        new_message = message[8..]
        Log.info("Redirecting deprecated method #{self.name}.#{message} to ##{new_message}")
        return self.new.send(new_message.to_sym, *args, **kwargs, &block)
      end

      # Send other methods which were moved to instance methods
      if self.method_defined? message
        Log.info("Redirecting deprecated method #{self.name}.#{message} to ##{message}")        
        return self.new.send(message, *args, **kwargs, &block)
      end
    end

    no_commands do
      # Loads the configuration settings, using {SeOpenData::Config#load}.
      # By default no parameters are supplied, so the defaults apply.
      #
      # However, if an environment variable `SEOD_CONFIG` is set, that
      # is used to set the path of the config file.
      #
      # This facility exists is so we can define the variable in cron
      # jobs, to specify different build environments (or "editions" in
      # the old open-data-and-maps terminology).
      #
      # Suggested usage is to use the defaults and allow the
      # `default.conf` (or `local.conf`, if present) to be picked up in
      # development mode (i.e. when `SEOD_CONFIG` is unset), and set
      # `SEOD_CONFIG=production.conf` for production environments. This allows
      # both of these to be checked in, and for the default case to be
      # development; it also allows developers to have their own
      # environments defined in `local.conf` if they need it (and this
      # won't get checked in if `.gitignore`'ed)
      def load_config
        require "se_open_data/config"
        if ENV.has_key? "SEOD_CONFIG"
          # Use this environment variable to define where the config is
          SeOpenData::Config.load ENV["SEOD_CONFIG"]
        else
          SeOpenData::Config.load
        end
      end

      # HTTP Gets the content of an URL, following redirects
      #
      # Headers can be provided with the headers parameter.
      #
      # Also sets the 'Accept: application/rdf+xml' header by default,
      # i.e. if it is not present in the headers parameter. You can set
      # the 'Accept' header to nil, or some preferred value to prevent this.
      #
      # @return the query content
      def fetch(uri_str, limit: 10, headers: nil)
        require "net/http"
        raise ArgumentError, "too many HTTP redirects" if limit == 0

        uri = URI(uri_str)
        request = Net::HTTP::Get.new(uri, headers)
        unless headers&.has_key? "Accept"
          request["Accept"] = "application/rdf+xml"
        end
        
        Log.info "fetching #{uri}"
        response = Net::HTTP.start(
          uri.hostname, uri.port,
          :use_ssl => uri.scheme == "https",
        ) do |http|
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          location = response["location"]
          Log.debug "redirected to #{location}"
          fetch(location, limit: limit - 1)
        else
          response.value
        end
      end
      
      def head(uri_str, limit: 10)
        require "net/http"
        raise ArgumentError, "too many HTTP redirects" if limit == 0

        uri = URI(uri_str)
        request = Net::HTTP::Head.new(uri)
        request["Accept"] = "application/rdf+xml"

        Log.debug "head #{uri}"
        response = Net::HTTP.start(
          uri.hostname, uri.port,
          :use_ssl => uri.scheme == "https",
        ) do |http|
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          response
        when Net::HTTPRedirection
          location = response["location"]
          Log.debug "redirected to #{location}"
          head(location, limit: limit - 1)
        else
          response
        end
      end

      def etag(uri_str, limit: 10)
        response = head(uri_str, limit: limit)
        response['etag'].to_s.strip
      end
      
      # Invoke a script.
      #
      # Be careful about the file name - sanitise it if it gets computed
      # or input - or it could be exploited!
      #
      # The default behaviour is to run the script, and return true if
      # it succeeds, and throw an exception if it doesn't exist or
      # returns a non-zero code (usually indicating failure).
      #
      # This can be fine tuned:
      # - allow_absent: if true, an absent script is not an error, instead nil is returned.
      # - allow_codes: can be set to one or an array of integer
      #   values the script should be allowed to return without raising
      #   an error. The code is returned instead of true.
      # - allow_failure: if true, failure is indicated by returning false, not raising
      #   an error.
      def invoke_script(script_with_args,
                             allow_codes: nil,
                             allow_absent: false,
                             allow_failure: false)
        script_name, *args = script_with_args.split(/\s+/);
        script_path = File.join(Dir.pwd, script_name)
        allow_codes = [allow_codes] if allow_codes.is_a? Integer

        if not File.exist? script_path
          if allow_absent
            Log.warn "no '#{script_name}' file found in current directory, continuing"
            return nil
          else
            raise "no '#{script_path}' file found in current directory"
          end
        end
        
        if system script_path, *args
          return true
        end

        if allow_codes.is_a? Array
          if allow_codes.include? $?.exitstatus
            return $?.exitstatus
          end
        end

        if allow_failure
          return false
        end
        
        raise "'#{script_name}' command in current directory failed"
      end
    end
    
    private

    # Gets an option by key, or a default
    #
    # Works around option defaults not being able to be nil (as this
    # is interpreted as no default, and the name of the option is
    # returned!). We set them to :, and this can be detected, and the
    # default returned.
    def _opt(key, default = nil)
      if !options.has_key? key.to_s or options[key] == :unset
        default
      else
        options[key]
      end
    end

    # escape double quotes in a string
    def esc2(val)
      val.to_s.gsub('"', '\\"').gsub('\\', '\\\\')
    end

    # escape single quotes in a string
    def esc1(val)
      val.to_s.gsub("'", "\\'").gsub('\\', '\\\\')
    end

    # URL-encode a string
    def urlencode(string)
      ERB::Util.url_encode(string)
    end

    # Run a command, capturing its output, printing it on failure.
    def system!(*cmd, **kwargs)
      out, status = Open3.capture2e(*cmd, **kwargs)
      unless status.success?
        raise "process failed with #{status.exitstatus}: #{cmd}\n#{out}"
      end
      status.success?
    end

    # Delegates to Deployment#deploy
    def deploy_files(**args)
      dest = [
        args[:to_server],
        args[:to_dir]
      ].filter {|it| it.to_s != ""}.join(":")
      Log.info "deploying to: #{dest}"
      SeOpenData::Utils::Deployment.new.deploy(**args)
    end

    # Checks if a string is a valid URL::HTTP (which includes HTTPS)
    # Returns the URL if true, else nil
    def valid_http_url?(value)
      uri = begin URI(value); rescue; end 
      if uri.is_a? URI::HTTP
        uri
      else
        nil
      end
    end

    # Checks if a string is a valid URL::HTTP (which includes HTTPS)
    # Returns the URL if true, else raises an exception
    def valid_http_url!(value)
      uri = valid_http_url? value
      return uri if uri
      raise "Not a valid HTTP URL: #{value}"
    end

    # download multiple files from HTTP locations below base_url into dest_path
    #
    # dest_path - path to a pre-existing directory to download into
    # items - an enumerable list of src, dst pairs. src can be a path or an URL.
    # dst must be a file path relative to dest_path
    # base_url - prepend this to src values which are paths, not URLs
    def fetch_many(dest_path:, items:, base_url: )
      base_url = valid_http_url! base_url

      dest_path = File.expand_path(dest_path)
      raise "Not a directory: #{dest_path}" unless Dir.exist? dest_path

      items.each do |src, dst|
        # Expand relative paths wrt the base_published_url
        uri = begin URI(src); rescue; end # nil on errors
        if uri.is_a? URI::HTTP
        # Ok, but can't expand this, use as-is
        elsif uri.is_a? URI::Generic and uri.host.to_s == "" # bare path
          # Can expand this
          src = base_url.merge(src).to_s
        else
          raise "Not a valid URL or path: #{src}"
        end

        # Download the content
        dst = File.expand_path(dst, dest_path)
        content = fetch src
        unless dst.start_with? dest_path
          raise "invalid destination, not below dest_path: #{{dst:, dest_path:}}"
        end
        Log.info "Writing #{dst}"
        # FIXME check dst exists?
        FileUtils.mkdir_p(File.dirname dst)
        IO.write dst, content
      end
      
      true
    end

    # Truncate a path
    #
    # Where level defines how to do this. It can be
    # nil, true -> take all the path
    # false -> take none of the path (so "" if relative, "/" if absolute)
    # 1 or more -> take this many components from the beginning
    # 0 or below -> remove this many components from the end 
    def truncate_path(path, level)
      pathname = Pathname(path)
      case level
      when nil, true
        return path
      when false
        return pathname.absolute? ? "/" : ""
      when Integer
        components = *pathname.each_filename
        level += components.size if level < 0
        level = 0 if level < 0
        path = File.join(components.take level)
        return pathname.absolute? ? "/"+path : path
      else
        raise "Invalid parameter level: #{level}"
      end
    end
    
    # Bulk import pre-existing files to a (possibly remote) virtuoso server
    #
    # graph_uri - the graph uri to insert into
    # user - the virtuoso user; defaults to 'dba'
    # password - the virtuoso password
    # pattern - like expression to match files to upload;
    #  see https://docs.openlinksw.com/virtuoso/likepredicate/
    # raise_on_error - set to true to trigger an exception on failure
    # upload_dir - path to existing directory containing RDF files to bulk upload
    # via - if set, files are transferred here and then uploaded from there there
    # can be a path, or an URL with a file or rsync schema
    # password - optional password for server. If omitted, upload is delegated
    #
    # returns an array of exit code and upload output from the upload command.
    # the exit code is zero on success, a numeric return code otherwise
    def bulk_import(
          remote_host: nil,
          directory: ,
          graph_uri:,
          pattern: '*',
          user: 'dba',
          password: nil,
          raise_on_error: false
        )
      # Info about isql commands here:
      # http://docs.openlinksw.com/virtuoso/virtuoso_clients_isql/
      output = ''
      result = nil
      cmd = ['isql-vt', '-H', 'localhost', '-U', user,
             'prompt=off', 'echo=off', 'verbose=off', 'banner=off', 'types=off']
      cmd += ['-P', password] if password
      cmd = ['ssh', '-T', remote_host] + cmd if remote_host
      
      graph_uri = URI(graph_uri)

      Open3.popen2e(*cmd) do |stdin, stdouterr, wait_thr|
        # Send the queries
        from_dir = directory if directory
        like_from_dir = from_dir.gsub(/%/, '[%]')+'%'

        # see https://vos.openlinksw.com/owiki/wiki/VOS/VirtBulkRDFLoader
        stdin << <<SQL
echoln "Clearing log for '#{esc2 esc1 from_dir}', this seem to avoid lingering import failures";
delete from DB.DBA.load_list where ll_file like '#{esc1 like_from_dir}%';

echoln "Clearing graph <#{graph_uri}>";
SPARQL CLEAR GRAPH '#{graph_uri}';
echoln "Loading triples from '#{esc2 File.join(from_dir, pattern)}' into <#{esc2 graph_uri}>";
ld_dir('#{esc1 from_dir}','#{esc1 pattern}','#{graph_uri}');
rdf_loader_run();

select ll_file, ll_error from DB.DBA.load_list where ll_file like '#{esc1 like_from_dir}' and ll_error is not null;
echoln $if $gt $rowcnt 0 $last[1] "No errors.";

echo "Existing errors which may need clearing: ";
select count(*) from DB.DBA.load_list where ll_file like '#{esc1 like_from_dir}' and ll_error is not null;

exit $if $gt $last[1] 0 1 not;

echo "Number of triplets in graph <#{graph_uri}> (must be > 0): ";
sparql select count (*) from <#{graph_uri}> where {?s ?p ?o};
exit $if $equ $last[1] 0 2 not;

echoln "Finished successfully.";
SQL
        stdin.close
        result = wait_thr.value
        #warn *stdouterr
        stdouterr.each do |line|
          output << line
        end 

      end
      
      if result == 0
        Log.debug "successful import"
        Log.debug output
        return 0, output
      else
        if raise_on_error
          raise "bulk import failed with result: #{result}\n"+output
        else
          Log.error("bulk import failed with result: "+result)
          Log.error(output)
          return result, output
        end
      end
    end

  end
end
