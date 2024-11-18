require_relative "../lib/load_path"
require "se_open_data/csv/schema"
require "minitest/autorun"

Minitest::Test::make_my_diffs_pretty!

describe SeOpenData::CSV::Schema do

  # Describe an input schema
  a_schema = SeOpenData::CSV::Schema.new(
    id: "foreign",
    fields: [
      {id: "foo",
       header: "Foo",
       desc: "just a foo"},
        
      {id: "bar",
       header: "Bar",
       desc: "a bar"},
      
      {id: "barBaz",
       header: "Bar Baz",
       desc: "bar and baz"}
    ]
  )
  
  # A CSV in schema_a with a blank line to skip
  in_csv = <<-HERE
Foo,Bar,Bar Baz
10,2,30

20,4,60
HERE

  # And an output schema
  b_schema = SeOpenData::CSV::Schema.new(
    id: "local",
    fields: [
      {id: "foo",
       header: "Foo",
       desc: "just a foo"},
      
      {id: "barNbaz",
       header: "Bar & Baz",
       desc: "bar and baz"}
    ]
  )


  
  describe "the first example converter" do
    
    # Define a simple conversion
    inopts = {skip_blanks: true, col_sep: "\t"}
    outopts = {}
    converter = SeOpenData::CSV::Schema.converter(
      from_schema: a_schema,
      to_schema: b_schema,
      input_csv_opts: inopts,
      output_csv_opts: outopts
    ) do | foo:, bar:, barBaz: |
      # Output row
      {
        foo: bar,
        barNbaz: barBaz.to_i - bar.to_i
      }
    end
    
    it "should perform the correct transform" do

      # Test the block directly
      in_data = {foo: 1, bar: 2, barBaz: 3}
      expected_out = {foo: 2, barNbaz: 1}
      converter.observer.on_row(**in_data) do |result|
        value(result).must_equal expected_out
      end

      # A TSV in schema_a with a blank line to skip
      in_tsv = <<-HERE
Foo\tBar\tBar Baz
10\t2\t30

20\t4\t60
HERE

      expected_csv = <<-HERE
Foo,Bar & Baz
2,28
4,56
HERE
      out_csv = ''
      StringIO.open(in_tsv, 'r') do |in_str|
        StringIO.open(out_csv, 'w') do |out_str|
          converter.convert(in_str, out_str)
        end
      end
      value(out_csv).must_equal expected_csv
    end
  end

  
  
  
  describe "a conversion with spurious inputs" do
    
    # Define another simple conversion, but this time
    # with spurious input field IDs
    converter = SeOpenData::CSV::Schema.converter(
      from_schema: a_schema,
      to_schema: b_schema
    ) do | foo:, bar:, barBaz:, spuriousId: |
      # Output row
      {
        foo: bar,
        barNbaz: barBaz.to_i - bar.to_i,
      }
    end
    
    it "should detect the missing input keywords in its conversion block" do
      # At runtime...
      
      out_csv = ''
      value(assert_raises(ArgumentError) {
              StringIO.open(in_csv, 'r') do |in_str|
                StringIO.open(out_csv, 'w') do |out_str|
                  converter.convert(in_str, out_str)
                end
              end
            }.message).must_match(/keyword parameters do not match .* :spuriousId/)
    end
  end

  describe "a conversion with spurious outputs" do
    
    # Define another simple conversion, but this time
    # with spurious output field IDs
    converter = SeOpenData::CSV::Schema.converter(
      from_schema: a_schema,
      to_schema: b_schema
    ) do | foo:, bar:, barBaz: |
      # Output row
      {
        foo: bar,
        barNbaz: barBaz.to_i - bar.to_i,
        spuriousId: foo, # This doesn't exist in the output schema_b
      }
    end
    
    it "should detect the missing output keys in its conversion block return hash" do
      # At runtime...
      
      out_csv = ''
      value(assert_raises(ArgumentError) {
              StringIO.open(in_csv, 'r') do |in_str|
                StringIO.open(out_csv, 'w') do |out_str|
                  converter.convert(in_str, out_str)
                end
              end
            }.message).must_match(/hash keys do not match .* spuriousId/)
    end
  end
end

                 
