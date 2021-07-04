require "se_open_data/utils/log_factory"

module SeOpenData
  class Murmurations
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default


    # ... FIXME
    # - need country code everywhere
    # - de-zero lat/lon?

    #
    # This validates the fields conform to the schema specification,
    # truncating selected text fields if they can be, omitting others
    # if empty, but it may also raise an exception if there is some
    # inconsistency (e.g. a locality without a country code).
    def self.write(uri_base, fields, output_file)
      # Fields expected:
      # Identifier,Name,Description,Organisational Structure,Primary Activity,Activities,Street Address,Locality,Region,Postcode,Country ID,Territory ID,Website,Phone,Email,Twitter,Facebook,Companies House Number,Qualifiers,Membership Type,Latitude,Longitude,Geo Container,Geo Container Latitude,Geo Container Longitude
      raise "No Identifier field!" unless fields.has_key? 'Identifier'
      data = {
        linked_schemas: %w(solidarity_economy_initiatives-v0.1.0),
        ld_uri: File.join(uri_base,fields['Identifier']),
        name: fields['Name'].to_s.strip.slice(0, 100),
        description: fields['Description'].to_s,
        website: fields['Website'].to_s,
        location: to_location(fields),
        geolocation: to_geolocation(fields),
        org_type_tags: to_org_type_tags(fields),
      }.delete_if {|k, v| v == nil || v.size == 0 }
      
      IO.write(output_file, JSON.pretty_generate(data))
    end

    def self.to_location(fields)
      location = {
        country: 'GB', ## FIXME a hack!  needs converting from a country name
        locality: fields['Locality'].to_s.slice(0, 100),
        region: fields['Region'].to_s.slice(0, 100),
      }.delete_if {|k, v| v.size == 0 }
      unless location.empty? || location[:country]&.size == 2
        raise "Country ID must be 2-letter ISO-3166-2 country code"
      end
      return location
    end

    def self.to_geolocation(fields)
      loc = [fields.fetch_values('Latitude', 'Longitude'),
             fields.fetch_values('Geo Container Latitude', 'Geo Container Longitude')]
              .map {|loc| loc.map &:to_f }
              .reject {|loc| loc == [0,0] }
              .first {|loc| loc.compact.size == 2}
      return nil unless loc
      return {lat: loc[0], lon: loc[1]}
    end
    
    def self.to_org_type_tags(fields)
      ids = fields['Organisational Structure'].to_s.split(";") + [fields['Qualifiers']]
      ids
        .map {|f| f.to_s.strip.slice(0, 100) } # normalise
        .reject {|f| f.size == 0}
      # FIXME expand?
    end
    
  end
end
