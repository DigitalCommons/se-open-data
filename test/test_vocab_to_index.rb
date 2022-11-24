# coding: utf-8
require 'se_open_data/vocab_to_index'
require 'minitest/autorun'
require 'linkeddata'

# Tests for SeOpenData::VocabToIndex.

Minitest::Test::make_my_diffs_pretty!

DataDir = __dir__+"/data"

describe SeOpenData::VocabToIndex do

  describe "using activities.ttl" do
    v2j = nil
    RDF::Reader.open(DataDir + '/activities.ttl') do |reader|
      v2j = SeOpenData::VocabToIndex.new(reader.to_enum)
    end
    

    it "at least this config should generate the expcted vocab datastructure" do
      result = v2j.aggregate({
                               languages: [:en, :fr],
                               vocabularies: [
                                 { uris: {
                                   "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities/" => "aci",
                                   "https:\/\/dev.lod.coop/essglobal/2.1/standard/base-membership-type/" => "bmt",
                                   }
                                 }
                               ],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(
        {
          :prefixes=>{
            "https://dev.lod.coop/essglobal/2.1/standard/activities/" => :aci,
            "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/" => :bmt,
          },
          :meta=>{
            :vocab_srcs=>[
              {
                :uris=>{
                  "https://dev.lod.coop/essglobal/2.1/standard/activities/"=>"aci",
                  "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/"=>"bmt"
                }
              }
            ],
            :languages=>[:en, :fr], # Note, lowercase, because from input config.
            :queries=>[]
          },
          :vocabs=>{
            "aci:": {
              :EN=>{
                :terms=>{
                  "aci:a01": "Agriculture and environment",
                  "aci:a02": "Mining and quarrying",
                  "aci:a03": "Craftmanship and manufacturing",
                  "aci:a04": "Energy production and distribution",
                  "aci:a05": "Recycling, waste treatment, water cycle and ecological restoration",
                  "aci:a06": "Construction, public works and refurbishing",
                  "aci:a07": "Trade and distribution",
                  "aci:a08": "Transport, logistics and storage",
                  "aci:a09": "Hospitality and food service activities",
                  "aci:a10": "Information, communication and technologies",
                  "aci:a11": "Financial, insurance and related activities",
                  "aci:a12": "Habitat and housing",
                  "aci:a13": "Professional, scientific and technical activities",
                  "aci:a14": "Administration and management, tourism, rentals",
                  "aci:a15": "Public administration and social security",
                  "aci:a16": "Education and training",
                  "aci:a17": "Social services, health and employment",
                  "aci:a18": "Arts, culture, recreation and sports",
                  "aci:a19": "Membership activities, repairing and wellness",
                  "aci:a20": "Household activities, self-production, domestic work",
                  "aci:a21": "International diplomacy and cooperation"
                },
                :title=>"Activities"
              },
              :FR=>{
                :terms=>{
                  "aci:a01": "Agriculture et environnement",
                  "aci:a02": "Mines et carrières",
                  "aci:a03": "Artisanat et manifacturier",
                  "aci:a04": "production et distribution de l'énergie",
                  "aci:a05": "Recyclage, traitement des déchets, cycle de l'eau et la restauration écologique",
                  "aci:a06": "Construction, travaux publics et remise à neuf",
                  "aci:a07": "Commerce et distribution",
                  "aci:a08": "Transport, logistique et entreposage",
                  "aci:a09": "Restauration, hôtellerie, catering",
                  "aci:a10": "Information, communication et technologies",
                  "aci:a11": "Finance, assurance et activités connexes",
                  "aci:a12": "Habitat et logement",
                  "aci:a13": "Activités professionnelles, scientifiques et techniques",
                  "aci:a14": "Administration et mangement, tourisme et location",
                  "aci:a15": "Administration publique et sécurité sociale",
                  "aci:a16": "Éducation et formation",
                  "aci:a17": "Services sociaux et santé",
                  "aci:a18": "Art, culture, loisirs et sports",
                  "aci:a19": "", "aci:a20": "", "aci:a21": ""
                },
                :title=>""
              }
            }
          }
        }
      )
    end
  end
end

