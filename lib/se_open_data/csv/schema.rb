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
      
      attr_reader :id, :name, :version, :description, :comment, :fields, :field_ids, :field_headers
      
      def initialize(id:, name: id, version: 0, description: '', comment: '', fields:)
        @id = id.to_sym
        @name = name.to_s
        @fields = normalise_fields(fields)
        @version = version
        @description = description
        
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
        raise ArgumentError, "Field with index #{last_ix} cannot be normalised, #{error.message}"
      end

      # Assumes that:
      # - Header names match the schema exactly
      # - There is one header which matches each field in the schema
      # - But there are no duplicate headers
      # - There may be unused headers
      #
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

        raise ArgumentError, "invalid header fields #{headers}: #{invalids.join('; ')}"
      end

      # Turns an array of values into a hash keyed by field ID.
      #
      # The values are validated during this process.
      #
      # This is used to creating a hash of input data keyed by our
      # field IDs, to pass to the row-transform block accepted by the
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
              "hash keys do not match '#{@id}' schema field IDs: #{id_hash.keys.join(', ')}"
      end

      # This implements the top-level DSL for CSV conversions.
      def self.converter(from_schema:, to_schema:,
                         input_csv_opts: DEFAULT_INPUT_CSV_OPTS,
                         output_csv_opts: DEFAULT_OUTPUT_CSV_OPTS,
                         &block)

        return Converter.new(
          from_schema: from_schema,
          to_schema: to_schema,
          input_csv_opts: input_csv_opts,
          output_csv_opts: output_csv_opts,
          &block)
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
      end

      # Defines a number of file conversion methods.
      #
      # Most notably, the method {#each_row} performs schema
      # validation and tries to facilitate simple mapping of row
      # fields, using the block provided to the constructor.
      class Converter
        attr_reader :from_schema, :to_schema, :block

        # Constructs an instance designed for use with the given input
        # and output CSV schemas.
        #
        # Rows are parsed and transformed using {#block}, which is
        # given a hash whose keys are {#from_schema} field IDs, and
        # values are the corresponding data fields.
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
        def initialize(from_schema:,
                       to_schema:,
                       input_csv_opts: {},
                       output_csv_opts: {},
                       &block)
          @from_schema = from_schema
          @to_schema = to_schema
          @input_csv_opts = input_csv_opts
          @output_csv_opts = output_csv_opts
          @block = block
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

        # Performs schema validation and tries to facilitate simple
        # mapping of row fields, using the {#block} provided to the
        # constructor (See {.new}.)
        #
        # The input stream is opened as a CSV stream, using
        # {#input_csv_opts}, likewise the output stream using
        # {#output_csv_opts}.
        #
        # Headers (assumed present) are read from the input stream
        # first, validated according to {#from_schema}, and used to
        # create a field mapping for the ordering in this file (which
        # is not assumed to match the schema's).
        #
        # Output headers are then written to the output stream (in the
        # order defined by {#to_schema}).
        #
        # Then each row is parsed and transformed using {#block}, then
        # the result written to the output CSV stream.
        #
        # @param input [String, IO] the file path or stream to read from
        # @param output [String, IO] the file path or stream to write to        
        def each_row(input, output)
          stream(input, output) do |inputs, outputs|
            csv_in = ::CSV.new(inputs, **@input_csv_opts)
            csv_out = ::CSV.new(outputs, **@output_csv_opts)
            
            # Read the input headers, and validate them
            headers = csv_in.shift
            field_map = @from_schema.validate_headers(headers) # This may throw
            
            # Write the output headers
            csv_out << @to_schema.field_headers
            
            csv_in.each do |row|
              # This may throw if validation fails
              id_hash = @from_schema.id_hash(row, field_map)

              new_id_hashes =
                begin
                  block_given? ? yield(id_hash) : @block.call(id_hash)
                rescue ArgumentError => e
                  # Try to reword the error helpfully from:
                  match = e.message.match(/missing keywords?: (.*)/)
                  if match
                    # To this:
                    raise ArgumentError,
                          "block keyword parameters do not match '#{@from_schema.id}'"+
                          " CSV schema field ids: #{match[1]}"
                  else
                    raise
                  end
                end

              # Normalise to an iterable:
              if new_id_hashes.nil?
                new_id_hashes = []
              elsif new_id_hashes.is_a? Hash
                new_id_hashes = [new_id_hashes]
              end

              new_id_hashes.each do |new_id_hash|
                # this may throw
                csv_out << @to_schema.row(new_id_hash)
              end
            end
          end
        end

        alias convert each_row
      end
    end
  end
end
