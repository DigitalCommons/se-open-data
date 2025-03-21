require 'csv'

module SeOpenData
  module CSV

    # Defines a CSV Schema
    #
    # This also defines a DSL for describing CSV translations via {self.converter}
    class Schema
      DEFAULT_INPUT_CSV_OPTS = {
        # Headers need to be off or else the logic needs to be changed.
        headers: false, 
        skip_blanks: true
      }
      DEFAULT_OUTPUT_CSV_OPTS = {
      }
      DEFAULT_CSV_SCHEMA_HEADERS = 
        %w(id header description comment primary)

      attr_accessor :id, :name, :version, :description, :comment
      attr_reader :fields, :field_ids, :field_headers, :primary_key
      
      def initialize(id:, name: id, version: 0, description: '', comment: '', fields:,
                     primary_key: [])
        @id = id.to_sym
        @name = name.to_s
        @fields = normalise_fields(fields)
        @version = version
        @description = description
        invalids = []
        @primary_key = primary_key.to_a.collect do |id|
          id = id.to_sym
          invalids << id unless @fields.find {|field| field.id == id} # validate
          id # copy
        end
        unless invalids.empty?
          raise "primary_key parameter contains these invalid field IDs #{invalids}"
        end
        
        # Pre-compute these. Trust that nothing will get mutated!
        @field_ids = @fields.collect { |field| field.id }
        @field_headers = @fields.collect { |field| field.header }
      end

      # Ensures that the fields are all instances of {Field}
      def normalise_fields(fields)
        last_ix = -1
        fields.collect.with_index do |field, ix|
          last_ix = ix
          if field.is_a? Field
            field.add_index(ix)
          else
            Field.new(index: ix, **field)
          end
        end
      rescue => error
        raise ArgumentError, "Field with index #{last_ix} cannot be normalised, #{error.message}",
              cause: error
      end

      
      # Validates an array of header names
      #
      # Assumes that:
      # - Header names match the schema exactly
      # - There is one header which matches each field in the schema
      # - But there are no duplicate headers
      # - There may be unused headers
      #
      # @param {Array<String>} an array of header names
      # @raise ArgumentError if any schema fields can't be matched or are duplicated
      # @return an array of row field indexes for schema field, or nil if that row field
      # is not included
      def validate_headers(headers) #FIXME
        invalids = []
        map = Array.new(@fields.size)
        @fields.each.with_index do |field, ix|
          header_ix = headers.find_index(field.header)
          if header_ix.nil?
            invalids.push "'#{field.header}' is missing"
          else
            if headers.rindex(field.header) != header_ix
              invalids.push "'#{field.header}' is duplicated"
            else
              map[ix] = header_ix
            end
          end
        end

        return map if invalids.empty?

        raise ArgumentError, "these header fields are invalid for this schema :#{@id}, #{headers}, because #{invalids.join('; ')}"
      end

      # Checks whether this schema has is compatible with another.
      #
      # This requires our fields to include all of its fields (just
      # the field id must match) and the primary key to be
      # identical
      #
      # Headers may differ, as for our purposes these are assumed to
      # be non-semantic labels which can vary. For instance a field
      # with an id `:contact` could have a header `Contact Name` in
      # one schema, and `Contact` in another, or even
      # `Ansprechperson`, and these would still be semantically
      # compatible.
      #
      # @param schema {SeOpenData::CSV::Schema} the schema to compare to
      # @throw RuntimeError if this schema isn't a superset the given
      def assert_superset_of(schema)
        if schema.primary_key != @primary_key
          raise RuntimeError.new(
                  "schema :#{@id} is not a superset of :#{schema.id} because "+
                  "its primary key #{@primary_key} does not match #{schema.primary_key}"
                )
        end

        missing = []
        schema.fields.each do |field1|
          field2 = field(field1.id)
          
          if field2.nil?
            missing.push(field1.id)
            next
          end
        end
        
        return if missing.empty?
        
        raise RuntimeError.new(
                "schema :#{@id} is not a superset of :#{schema.id} because "+
                "these fields are absent from it: #{missing}")
      end

      # Turns an array of values into a hash keyed by field ID.
      #
      # The values are validated during this process.
      #
      # This is used to creating a hash of input data keyed by our
      # field IDs, to pass to the Observer accepted by the
      # {Converter} class's constructor, {Converter.new}.
      #
      # @param row [Array] - an array of data values
      #
      # @param field_map [Array<Integer, nil>] - an array defining,
      # for each schema field, the index of the data field that it
      # refers to. 
      # @return [Hash<Symbol => Object>] the row data hashed by field ID
      #
      # @raise ArgumentError if field_map contains duplicates or nils,
      # or indexes which don't match a schema field index.
      #
      # @raise ArgumentError if row or field_map don't have the same
      # number of elements as there are schema fields.
      #
      def id_hash(row, field_map)
        hash = {}
        used = []
        # FIXME validate!
        # Check number of fields (Maybe - we should allow rows > fields,
        # but also fields > rows, if we allow 1:N row to field mapping)
        # Check type?
        raise ArgumentError, "field_map must have #{@fields.size} elements" unless
          field_map.size == @fields.size
        if row.size == 0
          raise ArgumentError, "incoming data has zero data fields, expecting schema :#{@id}"
        end
        
        @fields.each.with_index do |field, field_ix|
          datum_ix = field_map[field_ix]

          if datum_ix.nil?
            raise ArgumentError, "nil field index #{datum_ix} for schema :#{@id}"
          end
          if datum_ix < 0 || datum_ix >= row.size
            raise ArgumentError, "incoming data has #{row.size} fields so does not "+
                                 "include the field index #{datum_ix}, with schema :#{@id}"
          end
          if used[datum_ix]
            raise ArgumentError, "duplicate field index #{datum_ix} for schema :#{@id}"
          end

          hash[field.id] = row[datum_ix]
          used[datum_ix] = true
        end
        
        return hash
      end

      # Turns a hash keyed by field ID into an array of values
      #
      # The values are validated during this process.
      def row(id_hash)
        # FIXME validate!
        id_hash = id_hash.clone # Make a copy so we don't mutate anything outside
        
        row = @fields.collect do |field|
          raise ArgumentError, "no value for field '#{field.id}'" unless
            id_hash.has_key? field.id
          id_hash.delete field.id
        end

        return row if id_hash.empty?
        
        raise ArgumentError,
              "these hash keys do not match any field IDs of schema '#{@id}': #{id_hash.keys.join(', ')}"
      end

      # Looks up a field by ID
      #
      # @param id {Symbol|#to_sym}
      # @return {Field} the matching field, or nil if none found.
      def field(id)
        id = id.to_sym
        @fields.find {|field| field.id == id }
      end

      # Converts the schema into a hash mapping field IDs to field headers
      # @return {Hash<Symbol,String>} the hash of field IDs to field headers
      def to_h
        @fields.map {|field| [field.id, field.header] }.to_h
      end

      def self.load_csv(file, id:)
        data = {}
        opts = {headers: true}
        pk_ids = []
        fields = []
        version = Date.today.strftime('%Y%m%d')
        ix = 0
        
        ::CSV.foreach(file, **opts) do |row|
          if ix == 0
            if row.headers.sort != DEFAULT_CSV_SCHEMA_HEADERS.sort
              raise RuntimeError, "Unexpected CSV headers: "+
                                  "expected #{DEFAULT_CSV_SCHEMA_HEADERS.inspect}, "+
                                  "got #{row.headers.inspect}"
            end
          end
          
          (id, header, desc, comment, pk) = row.fields(*DEFAULT_CSV_SCHEMA_HEADERS)
          
          field = SeOpenData::CSV::Schema::Field.new(
            id: id,
            index: ix,
            header: header,
            desc: desc,
            comment: comment,
          )
          
          pk_ids << id if pk.to_s.downcase == 'true'
          fields << field
          ix += 1
        end

        return self.new(
                 id: id,
                 primary_key: pk_ids,
                 version: version,
                 description: '',
                 comment: '',
                 fields: fields,
               )
      end

      def self.load_yaml(file)
        require 'yaml'
        data = YAML.load_file(file)
        data.transform_keys!(&:to_sym)
        data[:fields].each { |field| field.transform_keys!(&:to_sym) }

        return self.new(**data)
      end

      
      protected

      def self.get_type(file)
        ext = File.extname(file)
        basename = File.basename(file, ext)

        case ext.downcase
        when '.yaml','.yml' then [:yaml, basename, ext]
        when '.csv' then [:csv, basename, ext]
        else raise ArgumentError,
                   "unknown file extension '#{ext}', specify the type explicitly"
        end
      end
        
      public
      
      # This loads a schema from a (.yaml or .csv or .tsv) file
      def self.load_file(file, type: nil)
        (_type, basename, ext) = get_type(file)
        type ||= _type
        
        case type
        when :yaml
          return load_yaml(file)

        when :csv
          return load_csv(file, id: basename)
          
        else
          raise ArgumentError, "#load_file received unknown schema file type: '#{type}'"
        end
      end

      def save_yaml(file)
        require 'yaml'
        data = {
          'id' => @id,
          'name' => @name,
          'version' => @version,
          'primary_key' => @primary_key,
          'comment' => @comment,
          'fields' => @fields.collect { |field| field.to_h }, 
        }
        File.open(file, 'w') do |file|
          file.write(YAML.dump(data))
        end
        return
      end
      
      def save_csv(file, **opts)
        data = {
          'id' => @id,
          'name' => @name,
          'version' => @version,
          'primary_key' => @primary_key,
          'comment' => @comment,
          'fields' => @fields.collect { |field| field.to_h }, 
        }
        unless opts.has_key? :write_headers
          opts[:write_headers] = true
          opts[:headers] = Schema::DEFAULT_CSV_SCHEMA_HEADERS
        end
        
        ::CSV.open(file, 'w', **opts) do |csv|
          @fields.each do |field|
            is_primary = primary_key.include? field.id
            csv << [field.id, field.header, field.desc, field.comment, is_primary]
          end
        end
        return
      end
      
      # This saves the schema to a file, the type defined by the file
      # extension, or the type: option
      def save_file(file, type: nil)
        (_type, _) = Schema.get_type(file)
        type ||= _type
        
        case type
        when :yaml
          return save_yaml(file)

        when :csv
          return save_csv(file)
          
        else
          raise ArgumentError, "#save_file received unknown schema file type: '#{type}'"
        end
      end

      
      # This implements the top-level DSL for CSV conversions.
      def self.converter(from_schema:, to_schema:,
                         input_csv_opts: DEFAULT_INPUT_CSV_OPTS,
                         output_csv_opts: DEFAULT_OUTPUT_CSV_OPTS,
                         **other_opts,
                         &block)

        return Converter.new(
          from_schema: from_schema,
          to_schema: to_schema,
          input_csv_opts: input_csv_opts,
          output_csv_opts: output_csv_opts,
          observer: block,
          **other_opts)
      end

      def self.write_converter(from_schema:, to_schema:,
                               path_or_io: nil)
        require 'erb'

        template = ERB.new(TEMPLATE, trim_mode: '-')
        content = template.result(binding)

        case path_or_io
        when String
          IO.write(path_or_io, content)
          File.chmod(0755, path_or_io)
        when ->(n) { n.respond_to? :write }
          path_or_io.write(content)
        when nil
          $stdout.write(content)
        else
          raise ArgumentError, "invalid path type: #{path.class}"
        end
      end

      # Defines a field in a schema
      class Field
        attr_reader :id, :index, :header, :desc, :comment

        # @param id [Symbol, String] a field ID symbol, unique to this schema
        # @param index [Integer] an optional field index (may be amended later with {#add_index})
        # @param header [String] the CSV header to use/expect in files
        # @param desc [String] an optional human-readable one-line description.
        # @param comment [String] an optional comment about this field
        def initialize(id:, index: -1, header:, desc: '', comment: '')
          @id = id.to_sym
          @index = index.to_i
          @header = header.to_s
          @desc = desc.to_s
          @comment = comment.to_s
        end

        # Used to amend the field index (non-mutating)
        #
        # @param index [Integer] the index to use
        # @return a new Field instance with the same values but the given index
        def add_index(index)
          Field.new(id: id, index: index, header: @header, desc: @desc, comment: comment)
        end

        # Converts the field definition to a hash.
        #
        # Primarily used for {Schema.save_file}, so omits the field index.
        #
        # @return a Hash object corresponding to this Field object.
        def to_h
          { 'id' => @id, 'header' => @header, 'desc' => @desc, 'comment' => @comment }
        end
      end

      # This is an base class for Observers to pass to the Converter.
      # It does nothing, and is expected to be subclassed to add some sort of
      # implementation.
      class Observer
        # Called for each CSV row being processed.
        # fields - a hash of fields keyed by ID (not headers)
        # It should yield for each output row with a hash keyed by output schema IDs
        # The return value is discarded.
        def on_row(**fields, &block)
        end

        # Called before parsing the CSV, when the headers
        # are available
        def on_header(header:, field_map:)
        end

        # Called after al the CSV rows are parsed
        def on_end
        end

      end

      # Defines a number of file conversion methods.
      #
      # Most notably, the method {#each_row} performs schema
      # validation and tries to facilitate simple mapping of row
      # fields, using the Observer instance provided to the constructor.
      class Converter
        attr_reader :from_schema, :to_schema, :observer, :opts

        # Constructs an instance designed for use with the given input
        # and output CSV schemas.
        #
        # Rows are parsed and transformed using an instance of
        # SeOpenData::CSV::Observer passed to the constructor and
        # accessible via the {#observer} method.

        # FIXME This which is given a
        # hash whose keys are {#from_schema} field IDs, and values are
        # the corresponding data fields.
        #
        # The block is normally expected to return another Hash, whose
        # keys are {#to_schema} fields, and values transformed data
        # fields.
        #
        # Additionally, it can return nil (if the input row should be
        # dropped), or an instance (like an array) implementing the
        # #each method which iterates over zero or more hash instances
        # (when each instances results in an output row).
        #
        # Note, the block can use the `next` keyword to skip a row, as
        # an equivalent to returning nil, or `last` to skip all
        # subsequent rows. (And in principle, the `redo` keyword to
        # re-process the same row, although this seems less useful.)
        #
        # @param from_schema [Schema] defines the input CSV {Schema}.
        # @param to_schema [Schema] defines the output CSV {Schema}.
        # @param input_csv_opts [Hash] options to pass to the input {::CSV} stream's constructor
        # @param output_csv_opts [Hash] options to pass to the output {::CSV} stream's constructor
        # @param block a block which transforms rows, as described.
        # @param reject_duplicate_pks - can be true (drop and warn), false
        # (just warn), or 'error' (raise an error). Defaults to false.
        # @param reject_invalid_pks - can be true (drop and warn), false
        # (just warn), or 'error' (raise an error). Defaults to false.
        def initialize(from_schema:,
                       to_schema:,
                       input_csv_opts: Schema::DEFAULT_INPUT_CSV_OPTS,
                       output_csv_opts: Schema::DEFAULT_OUTPUT_CSV_OPTS,
                       reject_duplicate_pks: false,
                       reject_invalid_pks: false,
                       observer:)
          @from_schema = from_schema
          @to_schema = to_schema
          @input_csv_opts = input_csv_opts
          @output_csv_opts = output_csv_opts
          @opts = {
            reject_invalid_pks: reject_invalid_pks,
            reject_duplicate_pks: reject_duplicate_pks,
          }
          case observer
          when Observer # we have an Observer
            @observer = observer 

          when Proc # Create an Observer wrapping the proc given using the old API
            @observer = Observer.new 
            @observer.define_singleton_method(:on_row) do |*args, **opts, &block|
              new_id_hashes = observer.call(*args, **opts)
              # Handle null, single, or multiple results
              case new_id_hashes
              when Hash # One item
                block.call(new_id_hashes)
              when Array # multiple items
                new_id_hashes.each {|hash| block.call(hash) }
              when nil # none, do nothing
              else # Something unexpected
                raise ArgumentError, "unexpected non-hash non-array result from "+
                                     "block: #{new_id_hashes.class}"
              end
            end

          else
            raise ArgumentError, "Invalid observer parameter: #{observer}"
          end

          # Validate @opts
          @opts.keys.each do |key|
            case @opts[key]
            when true, false, 'error' # no op
            else raise "invalid value for parameter '#{key}': #{@opts[key].inspect}"
            end
          end
        end

        # Accepts file paths or streams, but calls the block with streams.
        #
        # Opens streams if necessary, and ensures the streams are
        # closed after being returned.
        #
        # @param in_data [String, IO] the file path or stream to read from
        # @param out_data [String, IO] the file path or stream to write to
        # @param block a block to invoke with the input and output streams as parameters.
        # @return the result from the block
        def stream(in_data, out_data, &block)
          in_data = File.open(in_data, 'r') if in_data.is_a? String
          out_data = File.open(out_data, 'w') if out_data.is_a? String

          yield(in_data, out_data)
          
        ensure
          in_data.close
          out_data.close
        end

        # Converts a CSV input file with data in one schema into a CSV
        # output file with another.
        #
        # The input stream is opened as a CSV stream, using
        # {#input_csv_opts}.
        #
        # Headers (assumed present) are read from the input stream
        # first, validated according to {#from_schema}, and used to
        # create a field mapping for the ordering in this file (which
        # is not assumed to match the schema's).
        #
        # The resulting stream and the output parameter are then
        # passed to #enum_convert.
        #
        # @param input [String, IO] the file path or stream to read from
        # @param output [String, IO] the file path or stream to write to        
        def each_row(input, output) # FIXME test

          stream(input, output) do |inputs, outputs|
            index = 0
            csv_in = ::CSV.new(inputs, **@input_csv_opts)
            csv_out = ::CSV.new(outputs, **@output_csv_opts)

            # Read the input headers, and validate them
            headers = csv_in.shift
            field_map = @from_schema.validate_headers(headers) # This may throw

            @observer.on_header(header: headers, field_map: field_map)

            # Write the output headers
            csv_out << @to_schema.field_headers
            
            # The transform block expects ID->value hashes, Therefore,
            # add in a step to transform CSV rows (arrays) into those
            # (with some validation), and track the element count in
            # case of an error.
            enum_in = Enumerator::Lazy.new(csv_in) do |yielder, row|
              index += 1
              # This may throw if validation fails
              id_hash = @from_schema.id_hash(row, field_map)
              
              yielder << id_hash
            end
            
            transform(enum_in, csv_out)

            @observer.on_end
            
            return
          rescue => e
            raise ArgumentError, "error when converting element #{index} of data, "+
                                 "expected to have an input schema of :#{@from_schema.id}, "+
                                 "and a output schema :#{@to_schema.id}, but: #{e.message}",
                  cause: e
          end
        end

        # Converts a JSON input file with data in one schema into a CSV
        # output file with another.
        #
        # The data of interest is assumed to be in an array, possibly
        # nested inside other elements, as defined by data_path, which
        # names the nested elements to traverse (as per the Hash#dig
        # and Array#dig methods). If this parameter is an empty array,
        # the top-level data item is used.
        #
        # This array and the output parameter is then passed to
        # #enum_convert
        def json_convert(input, data_path, output)
          json = if input.is_a? String
                   IO.read(input)
                 else
                   input.read
                 end
          
          data = JSON.parse(json)

          if data_path.size > 0
            # Check it's a dig-able object 
            unless data.respond_to? :dig
              raise "Top level JSON element should be an object or an array, in #{json_file}"
            end
            
            data = data.dig(*data_path)
          end

          enum_convert(data, output)
        end

        # Converts an enumeration with data in one schema into a CSV
        # output file with another.
        # 
        # The schemas are defined by in_schema and out_schema. A
        # transform is performed on the items using the Observer
        # instance supplied to the constructor.
        #
        # Performs schema validation and tries to facilitate simple
        # mapping of row fields, using the {observer} provided to the
        # constructor (See {.new}.)
        #
        # The output stream is opened as a CSV stream using
        # {#output_csv_opts}.
        #
        # Headers of all items in the input data list are validated
        # validated according to {#from_schema}, and used to create a
        # field mapping for the ordering in this file (which is not
        # assumed to match the schema's).x
        #
        # Output headers are then written to the output stream (in the
        # order defined by {#to_schema}).
        #
        # Then each row is parsed and transformed using {Observer#on_row}, then
        # the result written to the output CSV stream.
        #
        # @param enum_in [Enumerator] an enumerable object containing Hashes with the expected form
        # @param output [String, IO] the file path or stream to write to        
        def enum_convert(enum_in, output) 
          # Validate we can use the data as we expect to
          if not enum_in.respond_to? :each
            raise "Incoming JSON elements should be contained in an Enumerable, not #{enum_in.class}"
          end

          # Open the output CSV stream
          ::CSV.open(output, 'w',
                     headers: @to_schema.field_headers,
                     write_headers: true) do |csv_out|

            # Pre-process the items in list using this block
            pp_enum_in = Enumerator::Lazy.new(enum_in) do |yielder, item|
              # Check it's a hash
              unless item.is_a? Hash
                raise "Incoming JSON elements must be objects not #{org.class}, in #{json_file}"
              end

              field_map = @from_schema.validate_headers(item.keys) # This may throw

              @observer.on_header(header: item.keys, field_map: field_map)
              
              id_hash = @from_schema.id_hash(item.values, field_map)
              
              # id_hash has now got the schema the transform method expects
              # (i.e. the normalised schema defined by @from_schema)
              yielder << id_hash
            end
            
            # Send the data, prepropressed through the above block,
            # through @observer
            transform(pp_enum_in, csv_out)

            @observer.on_end
          end
        end
        
        
        # Iterates over an enumerable enum_in, passing the headers and
        # rows to observer#on_header and observer#on_row, and
        # finalling calling observer#on_end.
        #
        #
        # - another hash, which is the transformed result,
        # - an array of transformed hashes, if the result corresponds to multiple elements
        # - nil, if there should be no data inserted into enum_out for this element.
        #
        # An exception may be raised by the block if there was an
        # error. In particular, if Ruby detects that the block is
        # passed an incomplete set of parameters at runtime, it will
        # raise an exception. This method attempts to catch these
        # errors and re-raise them with more helpful diagnostics
        # containing some context.
        #
        # The output hashes are validated. If the @to_schema includes
        # a primary key, the appropriate fields must be defined and
        # unique. They are cumulatively indexed to check there are no
        # duplicates. When an invalid or duplicate is found, a warning
        # is emitted on standard error, and that element is skipped.
        #
        # Also, all the fields defined by @to_schema must exist, or
        # likewise a warning is emitted and that element is skipped.
        #
        # Otherwise, each hash returned by the transformer block is
        # transformed into an array using to @to_schema#row, and that
        # is added into enum_out using the << operator.
        def transform(enum_in, enum_out)
          # Auto-vivifying hash recording primary keys seen
          pk_seen = Hash.new do |hash,key|
            hash[key] = Hash.new(&hash.default_proc)
          end

          enum_in.each do |id_hash|
            new_id_hashes = []
            begin
              @observer.on_row(**id_hash) do |new_id_hash|
                new_id_hashes << new_id_hash
              end
            rescue ArgumentError => e
              # Try to reword the error helpfully from:
              match = e.message.match(/(missing|unknown) keywords?: (.*)/)
              if match
                if match[1] == 'unknown'
                  # missing keywords
                  raise ArgumentError,
                        "Observer#on_row implementation must consume remaining keyword "+
                        "parameters for these '#{@from_schema.id}' schema field ids: #{match[2]}",
                        cause: e
                elsif match[1] == 'missing'
                  # unknown keywords
                  raise ArgumentError,
                        "Observer#on_row implementation's keyword parameters do not match "+
                        "'#{@from_schema.id}' schema field ids: #{match[2]}",
                        cause: e
                end
              else
                raise
              end
            end

            new_id_hashes.each do |new_id_hash|
              # this may throw
              row = @to_schema.row(new_id_hash)

              # validate any primary key fields
              unless @to_schema.primary_key.to_a.empty?
                pk = new_id_hash.fetch_values(*@to_schema.primary_key)
                pk_count = pk.compact.size
                expected_pk_count = @to_schema.primary_key.size

                if pk_count != expected_pk_count
                  next if reject? "invalid primary key value #{pk}", @opts[:reject_invalid_pks]
                end

                unless pk_seen.dig(*pk).empty?
                  next if reject? "duplicate primary key value #{pk}", @opts[:reject_duplicate_pks] 
                end
                
                # Mark this primary key as seen
                pk_seen.dig(*pk, true)
              end
              
              enum_out << row
            end
          rescue => e
            raise RuntimeError, "#{e.message}\nwhen parsing this row data:\n#{'%.160s' % id_hash}",
                  cause: e
          end
        end

        # Checks what behaviour to take from opt, and returns true or false to indicate
        # whether the row should be rejected; or raises an exception if it should be an error
        def reject?(msg, opt)
          case opt
          when true
            warn msg + " - dropping row"
          when false
            warn msg + " - keeping row"
          when 'error'
            raise msg
          else
            raise "invalid reject option: #{opt}"
          end

          opt
        end
        
        alias convert each_row
        alias csv_convert each_row
      end
      
      TEMPLATE =<<'END'
#!/usr/bin/env ruby
# coding: utf-8
#
# This script controls a pipeline of processes that convert the original
# CSV data into the se_open_data standard, one step at a time.
#
# We aim to put only logic specific to this project in this file, and
# keep it brief and clear. Shared logic should go into the {SeOpenData}
# library.
#
# This script can be invoked directly, or as part of the {SeOpenData}
# library's command-line API {SeOpenData::CliHelper}. For example, this
# just runs the conversion step (or specifically: a script in the
# current directory called `converter`):
#
#     seod convert 
#
# And this runs the complete chain of commands generating and
# deploying the linked data for this project, as configured by
# `settings/config.txt`:
#
#     seod run-all
#
# See the documentation on [`seod`]({SeOpenData::CliHelper}) for more
# information.

require 'se_open_data/setup'
require 'se_open_data/csv/schema/types'
#require 'normalize_country'

# A class which defines callback methods #on_header, #on_row, and #on_end, 
# that are called during the conversion process.
class Observer < SeOpenData::CSV::Schema::Observer
  Types = SeOpenData::CSV::Schema::Types

  # Set up anything persistent you need here  
  def initialize(setup:)
    super()
    @geocoder = setup.geocoder
  end

  # Called with an array of header fields, and a field_map, which
  # is an array of integers denoting the schema index for each header
  def on_header(header:, field_map:)
    @ix = 0
  end
  
  def on_row(
        # These parameters match source schema field ids
        <%- from_schema.fields.each do |field| -%>
        <%-   if field.index+1 < from_schema.fields.size -%>
        <%=      field.id %>:,
        <%-   else -%>
        <%=      field.id %>:
        <%-   end -%>
        <%- end -%>
      )

    # Examples of common preliminary steps:
    # addr = Types.normalise_addr(city, state_region, postcode, country)
    # warn "row #{record_id} #{addr}"
    # country_id = NormalizeCountry(country)
    geocoded = nil #@geocoder.call(addr)
    @ix += 1

    # Replace these with the actual values to write.
    # You may yield zero or many times if desired, and the equivalent number
    # of rows will be emitted.
    <%- to_schema.fields.each do |field| -%>
    <%    case field.index+1 -%>
    <%-   when 1 then %>yield <%= field.id -%>: @ix,
    <%-   when to_schema.fields.size -%>      <%= field.id %>: nil
    <%    else %>      <%= field.id %>: nil,
    <%-   end -%>
    <%- end -%>
  end

  # Called after all the rows have been processed
  def on_end
  end

end

SeOpenData::Setup
  .new
  .convert_with(observer: Observer)
END
    end
  end
end

