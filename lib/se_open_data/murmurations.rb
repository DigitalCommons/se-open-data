require "se_open_data/utils/log_factory"
require "json"
require "httparty"
require 'normalize_country'

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
      dataset_uri = File.join(uri_base, '') # URL needs trailing slash
      org_uri = File.join(uri_base, fields['Identifier'])
      # primary_url is mandatory in the organizations_schema (at time of writing)
      # So use org_uri as a fallback option, else profile won't register.
      primary_url = fields['Website'].to_s
      primary_url = org_uri if primary_url == ''
      data = {
        linked_schemas: %w(organizations_schema-v1.0.0),
        name: fields['Name']&.to_s.strip.slice(0, 100),
        # nickname:
        primary_url: primary_url, 
        tags: [
          'https://digitalcommons.coop/mykomaps/',
          dataset_uri,
        ],
        urls: [
          {
            name: 'created by',
            url: 'https://digitalcommons.coop/mykomaps/',
          },
          {
            name: 'linked-data organisation uri',
            url: org_uri,
          },
          {
            name: 'linked-data dataset uri',
            url: dataset_uri,
          },
        ],
        description: fields['Description']&.to_s,
        # mission:
        # status: 
        full_address: to_full_address(fields),
        country_iso_3166: fields['Country ID'],
        geolocation: to_geolocation(fields),
        # image:
        # header_image:
        # images:
        # rss:
        # relationships:
        # starts_at:
        # ends_at:
        contact_details: to_contact_details(fields),
        telephone: fields['Phone'],
        # geographic_scope: 
      }.delete_if {|k, v| v == nil || v.size == 0 }
      
      IO.write(output_file, JSON.pretty_generate(data))
    end

    def self.to_contact_details(fields)
      if fields['Email'].to_s.length > 0
        {
          email: fields['Email'],
          # contact_form:
        }
      else
        nil
      end
    end
    
    def self.to_full_address(fields)
      location = [
        fields['Street Address'].to_s,
        fields['Locality'].to_s,
        fields['Region'].to_s,
        NormalizeCountry(fields['Country ID'], to: :short).to_s,
      ].filter {|v| v.size > 0 }
      return location.join(', ')
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
