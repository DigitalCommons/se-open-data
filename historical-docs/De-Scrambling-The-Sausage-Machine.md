
# De-Scrambling the Sausage Machine

The "sausage machine" is our diminutive term for the algorithm in the
`open-data` project (which itself was derived from the
`open-data-and-maps` project). It takes in data from 3rd parties,
munges it, and spits out linked data which can be used as content for
the `sea-map` project.

This is an attempt at (re)documenting what the "sausage machine" does,
identify common patterns between all the different projects and
"editions" thereof, all of which vary in their details in a way which
is hard to understand.

## Folder structure

Currently there are sub-directories for each project (e.g. Oxford,
Newbridge, DotCoop), within which are sub-directories for particular
data sets, often named after the date of publication.

These data-set directories contain a number of makefiles, which both
supply configuration, and invocations for various scripts which do the
munging.

They share some scripts and makefiles from the `tools/se_open_data/`
directory.

However, some of the scripts are stored in the directory in question,
when they are specific to that data set. Well, probably. There's also
a lot of cut-and-pasting of files going on, so a lot of
duplication. This is part of what's hard to untangle.

Data is generated into the `generated-data` sub-folder within the
data-set directories. This is then uploaded onto the target
server. The uploaded data includes:

- Static linked-data for online publication on the web, in the form
  of:
  - Human-readable HTML
  - RDF
  - TTL
- Linked data and scripts for importing into Virtuoso:
  - all.rdf
  - essglobal_vocab.rdf
  - global.graph
  - loaddata.sql
  - organisational-structure.skos
- .htaccess redirection rules for w3id URIs
- One or more canned SPARQL queries for sea-map to use on the data

## Overview

The logical sequence of steps is:

- Start with a CSV file of data from some 3rd party source
- Convert it to a standard CSV schema `standard.csv` in
  `generated-data/` with a case-specific `csv.mk` file (which often
  invokes a `converter.rb` script, amongst others)
- This may then generate some intermediates in `generated-data/csv/`, for instance:
  - The [README.md] document says `initiatives.csv` (an
    intermediate file) and `report.csv` (copy of the original, but
    with a column of comments added)... but in practice this varies.
  - The `ica-youth-network` project creates `with_ids.csv` and `cleared_errors.csv`
  - ... and so on (TODO add more detail here?)
  *dean: The specified processes for conversion are most of the time at the level of a specific project. I.e. ica-youth-network requires specific data clearing procedures, this should not and does not need to be shared with other projects (hence it is kept and used only in the ica-youth-network project and not in the standard library.)*
  
- Next, generate RDF/TTL/HTML using `generate.mk` which invokes
  `csv-to-rdf.rb`
- Deploy the generated static-data files to the web-server using
  `deploy.mk`
- Generate the linked-data graph and upload to the Virtuoso server
  using `triplestore.mk`

This translates to executing (with the appropriate 'edition'
configuration) these makefiles in the following order:

- `csv.mk`
- `generate.mk`
- `deploy.mk`
- `triplestore.mk`

(There is work in progress to add a step of downloading the source
data from Lime Survey in cases which need it. TODO update this later.)

## The standard CSV format and `converter.rb`

The standard CSV format documented in the [README.md] file is (the
rest of this section is essentially quoting that directly) defined in
the module
[SeOpenData::CSV::Standard::V1](../tools/se_open_data/csv/standard.rb). At
the time of writing, this contains the following:

```
id: "Identifier",
name: "Name",
description: "Description",
organisational_structure: "Organisational Structure",
primary_activity: "Primary Activity",
activities: "Activities",
street_address: "Street Address",
locality: "Locality",
region: "Region",
postcode: "Postcode",
country_name: "Country Name",
homepage: "Website",
phone: "Phone",
email: "Email",
twitter: "Twitter",
facebook: "Facebook",
companies_house_number: "Companies House Number",
latitude: "Latitude",
longitude: "Longitude",
geocontainer: "Geo Container",
geocontainer_lat: "Geo Container Latitude",
geocontainer_lon: "Geo Container Longitude"
```

*Aside: I've checked this matches the current definition -- Nick*

The text to the left of the colon is the key or symbol that's used to
reference the values internally – we'll get back to this. The text to
the right of the colon is the name that will be used for each field in
the standard CSV that's generated.

For example, the CSV headers will appear like this, with each of the
initiative's Identifiers appearing on the Identifier column, names in
the Name column and so on:

```
| Identifier | Name | Description | ... | Geo Container Latitude | Geo Container Longitude |
```

Within each project there is a script called `converter.rb`. These can
be found in each of the `data/[project_name]/[project_version]/`
folders.

`converter.rb` takes the values from the input CSV and pipes them into
the output CSV. The data can either be passed straight through to the
output or it can be processed before passing it on.
*dean: converter.rb is not responsible for the pipeline. csv.mk is the script which is responsible for managing the pipeline of execution and `converter.rb` quite literally just creates a mapping {A -> B} (A being a field in the original file and B - the resulting file, Note: the mapping can be both a relational mapping or a function applied to A)*

To pass the data through just assign the header name to the symbol
from the standard. For instance, if the files that we want to use as
the Identifier is in a field called ID in the source data then
`InputHeaders` should contain a key of id (the symbol for Identifier
in the output) with a value of ID (the header of the field containing
the Identifier in the source). E.g.:

```
InputHeaders = {
  id: "ID",
  name: "Name",
  description: "Description"
}
```

When the script is run, it will run through each row in the source CSV
and place each item in the ID column in the Identifier column of the
output, the Name fields in the Name output column and the Description
fields in the Description column.

If we need to change any of the source data or process it in some
other way – checking for validity for instance - then we can define a
method with the same name as the symbol we want to populate. The
output of the method will then be passed to the output. For instance,
if we want to combine several fields from the input into one in the
output we can use the following:

```
InputHeaders = {
  id: "ID",
  name: "Name",
  description: "Description"

  # ... Other headers

  address1: "Address1",
  address2: "Address2",
  address3: "Address3"
}

def street_address
  [
	!address1.empty? ? address1 : nil,
	!address2.empty? ? address2 : nil,
	!address3.empty? ? address3 : nil
  ].compact.join(OutputStandard::SubFieldSeparator)
end
```

This method returns a string made up of the three fields address1,
address2 and address3 (if they're populated). Each of these fields
have been added to the InputHeader map so they can be referenced in
the method.


[Later] This script is often supplemented by others. There is a full
case study in [CSV_MAPPING.md]

## Editions

What are "editions"? The [README.md] says these are "a way to work in
multiple environments depending on our needs. We might, for instance,
want to try something new out without overwriting existing data."

Effectively, they're a makefile in a project directory which contains
config settings which override defaults in common.mk (in the project
directory).

When running the makefiles, you must supply an edition name -
otherwise it will not run.

The names tend to be `test.mk`, `experimental.mk`, possibly with a
year appended, then a `final.mk`. The differences in these files tend
to be server/account addresses, and some URIs.

From this, they seem to specify parameters specific to deployments,
and most of all, allow production and development builds, and
deployment to different servers. Usually these are called
"environments" in the terminology of other build-tools I've
encountered.

I suspect the server specifics of development deployments shouldn't be
in version control, if these change from developer to developer. It
might be sensible to separate out production vs development settings,
from the actual account/server names used in different circumstances.

## Variance between projects

Reviewing the projects in `open-data` I find the following examples
(these are names of top-level directories containing projects), along
with the data sets and "editions" as shown in nested bullet
lists. Note, this is not a literal directory structure, but an
overview.

- `co-ops-uk/`
  - `2015-06/`
    - `Cooperative_Economy_Open_Dataset_2015_06.csv` - raw data
	- `Makefile` - drives the process, documented inline as *obsolete*
	- `generate-triples.rb` - script
	- `css/` (HTML styles, includes `links.css`, `style.css`)
  - `2016-06/`
    - `README.md` - describes this early processor
    - `Pre-release/open_data_*.csv` - raw data
	- `co-operativeeconomy_opendataextract2016/2016open_data_*.csv` - more raw data
	- `os_postcode_cache.json`, `postcode_lat_lng.json` - cached data
	- `Makefile` - drives the process, presumably obsolete too
	- `generate-triples.rb`, `initiatives2os_postcode_cache.rb` - scripts
	- `css/` (HTML styles, `links.css`, `style.css`)
    - `sparql/` - some SPARQL queries
  - `2017-06/`
    - `README.md` - describes this early processor
    - `co-ops-uk-csv-data/open_data_*.csv` - raw data
	- `co-ops-uk-csv-test-data/open_data_*.csv` - test raw data
	- `common.mk` - config
	- `editions/` - more config (`test2017.mk`, `test20172.mk`, `final.mk`)
	- `csv.mk` - makefile for normalising csv
	- `scripts/` (`co-ops-uk-extract-org-id.rb`, `co-ops-uk-extract-ownership_classification.rb`, 
	  `co-ops-uk-extract-registrar.rb`)
	- `css/` (HTML styles, includes `links.css`, `style.css`)
    - `sparql/` - some SPARQL queries
  - `2019-06/`
    - `README.md` - describes this early processor
	- `co-ops-uk-csv-data/open_data_*.csv` - raw data
	- `co-ops-uk-csv-test/open_data_*.csv` - test raw data
	- `co-ops-uk-orgs-converter.rb`, `co-ops-uk-outlets-converter.rb` - scripts
	- `common.mk` - config
	- `editions/` - more config (`test.mk`, `test2019.mk`, `final.mk`)
	- `csv.mk` - makefile for normalising csv
	- `scripts/` (`co-ops-uk-extract-org-id.rb`, `co-ops-uk-extract-ownership_classification.rb`, 
	  `co-ops-uk-extract-registrar.rb`)
	- `css/` (HTML styles, includes `links.css`, `style.css`)
    - `sparql/` - some SPARQL queries
- `newcastle-pilot/`
  - `2018-08-15/`
    - `original-data/DA-Groups-and-Engagement-*.csv` - raw data
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`)
	- `csv.mk` - makefile for normalising csv
	- `converter.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
  - `2018-10-mapjam/`
    - `README.md` - documentation
	- `images/conductor-delete-graph.png` - documentation
    - `original-data/*.csv` - raw data
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`, `experimental-new-server.mk`)
	- `csv.mk` - makefile for normalising csv
	- `converter.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
  - `2019-07-03/`
    - `README.md` - documentation
	- `images/conductor-delete-graph.png` - documentation
    - `original-data/*.csv` - raw data
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`, `experimental-new-server.mk`)
	- `csv.mk` - makefile for normalising csv
	- `converter.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)    
- `oxford`
  - `pilot/`
    - `original-data/*.csv` - raw data
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`, `experimental-new-server.mk`, `final.mk`)
	- `csv.mk` - makefile for normalising csv
	- `converter.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
- `dotcoop/`
  - `domains2018-04-24/`
    - `cache/` - cached data, `outlets.csv`, includes description in `README.md`
	- `common.mk` - config
	- `editions/` - more config (`test.mk`, `experimental.mk`, `experimental-new-server.mk`, `final.mk`)
	- `csv.mk` - makefile for normalising csv
	- `converter.rb`, `match-with-coops-uk.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
    - `sparql/` - some SPARQL queries
  - `domains2019-10-03/`
    - `docs/` - PDF documentation of geocaching data
    - `cache/` - cached data, `outlets.csv`, includes description in `README.md`
	- `geodata_cache.json` - cached data *(generated, not checked in)*
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`)
	- `Makefile` - links csv normalisation to later steps
	- `csv.mk` - makefile for normalising csv
	- `converter.rb`, `match-with-coops-uk.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
    - `sparql/` - some SPARQL queries
- `ica-youth-network/`
  - `demo/` - Created by Dean, first pass
    - `original-data/Youth-ledCoops.csv` - raw data
	- `common.mk` - config
	- `editions/` - more config (`experimental.mk`)
    - `csv.mk` - makefile for normalising csv
    - `clear_csv_errors.rb`, `converter.rb`, `test.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
  - `test/` - Created by Dean, second pass, removes makefiles in favour of Ruby scripts
    - `original-data/Youth-ledCoops.csv` - raw data
	- `settings/defaults.txt` - config (`config.txt` generated by `load_config.rb`)
    - `csv.rb` - Ruby script for normalising csv
    - `clear_csv_errors.rb`, `converter.rb`, `load_config.rb` - scripts
	- `css/` (HTML styles, includes `links.css`, `style.css`)
  
    
Plus, the following cases look like they might be vestigial project
directories, but look abandoned. They do not have the usual csv
conversion machinery either, just a data file.

- `susy/`
- `umap/`

### csv.mk

- `co-ops-uk/`: both `csv.mk` files here are identical. Older Makefiles are obsolete.
- `dotcoop/`: 2 projects,
  - minor differences between them:
    - latter project adds a "global" `geodata_cache.json` supplementing `postcode_lat_lng.json`
    - also adds `corrected-geo-data.csv` data, a cleaned-up version of `standard.csv`
  - compared to `co-ops-uk`:
    - alters/adds extra processing steps
- `newcastle-pilot/`: 3 projects - 2018-08-15, 2018-10-mapjam, 2019-07-03
  - 2018 cases are essentially identical
  - 2019 case drops ID de-dupe step, and step to create a simpler
    version of `standard.csv`, `uri-name-postcode.csv`
  - 2018 somewhat similar to co-ops-uk, but add a `reports.csv`
    (annotated version of raw data), and no need to merge outlets and organisations data	
- `oxford/pilot/`
  - just one dataset/csv.mk, despite multiple years of data - implies
    successive data is consistent.
  - no separate orgs/outlets datasets
  - essentially identical to newcastle-pilot/2019-07-03/csv.mk
- `ica-youth-network/`
  - very new, added by Dean
  - just one dataset/edition
  - well, two: `demo` is a makefile-driven version, `test` is a
    Ruby-script driven one superseding it.
  - the csv.mk here most resembles the one for oxford - besides the
    cut-and-paste ancestry is betrayed by a comment declaring it is
    for oxford.
  - an extra step to clear CSV errors `clear_csv_errors.rb` has been added
  - and another to add unique IDs `add-unique-id.rb`
  - the step to convert postcodes into lat/long is dropped
  

### common.mk

- `co-ops-uk/`: both `common.mk` files here are identical. Older Makefiles are obsolete.
- `dotcoop/`: identical, except no sameas csv in the latter case
  - compared with `co-ops-uk/`:
    - sameas csv added in first case (but in this respect identical in latter)
	- some TEST_INITIATIVE_IDENTIFIERS added (to "test the deployment")
- `newcastle-pilot/`: all identical. Essentially the same as `co-ops-uk/`
- `oxford/pilot/`: essentially the same as `co-ops-uk/`
- `ica-youth-network/`: essentially the same as `co-ops-uk/`


### Data schema

#### co-ops-uk

##### 2015-06

Cooperative_Economy_Open_Dataset_2015_06.csv
- Registered Number
- Organisation Name
- Co-ops UK Identifier
- Gross Sales
- Turnover
- Turnover (adjusted for Gross Sales)
- Number of Members
- Profit Before Tax
- Shareholder Funds
- Number of Employees (headcount)
- Year End Date
- Source
- Registered Street
- Registered City
- Registered State/Province
- UK Nation
- Registered Address - Area
- Code Level 1 Description
- Code Level 2 Description
- Code Level 3 Description
- Code Level 4 Description
- Code Level 5 Description
- Registered Postcode
- Is Most Recent

##### 2016-06

open_data_administrative_areas_0.csv
- CUK Organisation ID
- Registered Name
- Area Type
- Area Name


open_data_economic.csv
- CUK Organisation ID
- Registered Name
- Turnover
- Profit before tax
- Member/Shareholder Funds
- Memberships
- Employees
- Is Most Recent?
- Year End Date
- Economic Year

open_data_organisations.csv 
- CUK Organisation ID
- Registered Number
- Registrar
- Registered Name
- Trading Name
- Legal Form
- Registered Street
- Registered City
- Registered State/Province
- Registered Postcode
- UK Nation
- SIC Code
- SIC section
- SIC code  - level 2
- SIC code  - level 2 description
- SIC code  - level 3
- SIC code  - level 3 description
- SIC code  - level 4
- SIC code  - level 4 description
- SIC code  - level 5
- SIC code  - level 5 description
- Sector - Simplified, High Level
- Ownership Classification
- Registered Status
- Incorporation Date
- Dissolved Date

open_data_outlets.csv 
- CUK Organisation ID
- Registered Name
- Outlet Name
- Street
- City
- State/Province
- Postcode
- Description
- Phone
- Website

##### 2017-06

open_data_administrative_areas_0.csv - unchanged

open_data_economic.csv - unchanged

open_data_organisations.csv - unchanged

open_data_outlets.csv - unchanged


##### 2019-06

open_data_administrative_areas_0.csv - unchanged

open_data_economic.csv -addition: field 8, GVA

open_data_organisations.csv - unchanged

open_data_outlets.csv - unchanged


open_data_outletsold.csv - as open_data_outlets.csv


#### dotcoop

There seems to be no raw data in the domains2018-04-24 project, just
domains2019-10-03.

SolidarityEconomyExport.20200119.csv
- Domain
- RegistrantId
- CreationDate
- Organisation
- StreetNumber
- StreetName
- StreetAddress
- City
- State
- Country
- PostCode

#### newcastle-pilot

##### 2018-08-15

Only spreadsheet data, not tabular

##### 2018-10-mapjam/2018-10-23

- Name
- Postcode
- Lat/Long
- Web
- Tags
- Contact Person
- Email
- Phone
- Address
- Notes from post it
- Description from website

###### 2018-10-mapjam/2018-11-06 

No changes.

###### 2018-10-mapjam/2018-12-19

Added these initial fields:
- Contacted
- Responded
- Met

##### 2018-10-mapjam/2018-12-19

No changes.

##### 2019-07-03

All data sets:
- id
- submitdate
- lastpage
- startlanguage
- seed
- startdate
- datestamp
- name
- address[a]
- address[b]
- address[c]
- address[d]
- address[e]
- address[a1]
- website
- facebook
- twitter
- description
- activity
- secondaryActivities[SQ002]
- secondaryActivities[SQ003]
- secondaryActivities[SQ004]
- secondaryActivities[SQ005]
- secondaryActivities[SQ006]
- secondaryActivities[SQ007]
- secondaryActivities[SQ008]
- secondaryActivities[SQ009]
- secondaryActivities[SQ010]
- secondaryActivities[SQ011]
- secondaryActivities[SQ012]
- secondaryActivities[SQ013]
- structure[SQ001]
- structure[SQ002]
- structure[SQ003]
- structure[SQ004]
- structure[SQ005]
- structure[SQ006]
- structure[SQ007]
- structure[SQ008]
- structure[SQ009]
- structure[SQ010]
- structure[SQ011]
- structure[SQ012]
- network
- values[SQ001]
- values[SQ002]
- values[SQ003]
- values[SQ004]
- values[SQ005]
- websiteConsent
- contactName
- contactEmail
- contactPhone
- attendWorkshop
- contactConsent[SQ001]
- contactConsent[SQ002]
- suggestedInitiatives
- interviewtime
- groupTime12
- nameTime
- addressTime
- websiteTime
- facebookTime
- twitterTime
- descriptionTime
- activityTime
- secondaryActivitiesTime
- structureTime
- networkTime
- valuesTime
- websiteConsentTime
- groupTime13
- contactNameTime
- contactEmailTime
- contactPhoneTime
- attendWorkshopTime
- contactConsentTime
- suggestedInitiativesTime

#### oxford

##### 2019-01-17
- Response ID
- Name
- Street
- Town
- Postcode
- Email
- Phone
- Website
- Facebook
- Twitter
- Legal forms
- Activities

##### 2019-05-09
- ﻿id
- name
- address[a]
- address[b]
- address[c]
- address[d]
- address[e]
- address[a1]
- email
- phone
- website
- facebook
- twitter
- hours[SQ001]
- hours[SQ001comment]
- hours[SQ002]
- hours[SQ002comment]
- hours[SQ003]
- hours[SQ003comment]
- hours[SQ004]
- hours[SQ004comment]
- hours[SQ005]
- hours[SQ005comment]
- hours[SQ006]
- hours[SQ006comment]
- hours[SQ007]
- hours[SQ007comment]
- contactName
- contactDetails
- description
- values[SQ001]
- values[SQ002]
- values[SQ003]
- values[SQ004]
- values[SQ005]
- structure[SQ001]
- structure[SQ002]
- structure[SQ003]
- structure[SQ004]
- structure[SQ005]
- structure[SQ006]
- structure[SQ007]
- structure[SQ008]
- structure[SQ009]
- structure[SQ010]
- structure[SQ011]
- structure[SQ012]
- activity
- secondaryActivities[SQ002]
- secondaryActivities[SQ003]
- secondaryActivities[SQ004]
- secondaryActivities[SQ005]
- secondaryActivities[SQ006]
- secondaryActivities[SQ007]
- secondaryActivities[SQ008]
- secondaryActivities[SQ009]
- secondaryActivities[SQ010]
- secondaryActivities[SQ011]
- secondaryActivities[SQ012]
- secondaryActivities[SQ013]
- network
- websiteConsent

###### 2019-05-16 and all subsequent (to 2019-08-28)

These fields added after `id`:
- submitdate
- lastpage
- startlanguage
- seed
- startdate
- datestamp

These fields added after `websiteConsent`:
- contactConsent
- suggestedInitiatives
- interviewtime
- groupTime9
- nameTime
- addressTime
- emailTime
- phoneTime
- websiteTime
- facebookTime
- twitterTime
- hoursTime
- contactNameTime
- contactDetailsTime
- groupTime10
- descriptionTime
- valuesTime
- structureTime
- activityTime
- secondaryActivitiesTime
- networkTime
- groupTime11
- websiteConsentTime
- contactConsentTime
- suggestedInitiativesTime


#### ica-youth-network

Youth-ledCoops.csv
- Organization Type
- Name
- name
- Region
- Country
- City
- Latitude
- Longitude
- Size
- Type
- Sector
- Address
- Description
- Additional Details
- Website
- Email

#### ica

CiviCRM_Contact_Search_members_04052020.csv
- Organisation Name
- Country
- Super-region
- Main-Street Address
- Main-Supplemental Address 1
- Main-Supplemental Address 2
- Main-City
- Main-Postal Code
- Main-Phone-Phone
- Website
- Typology
- Structure Type
- Economic activity (primary)
- Economic activities (additional)

#### Target format

standard.csv
- Identifier
- Name
- Description
- Organisational Structure
- Primary Activity
- Activities
- Street Address
- Locality
- Region
- Postcode
- Country Name
- Website
- Phone
- Email
- Twitter
- Facebook
- Companies House Number
- Latitude
- Longitude
- Geo Container
- Geo Container Latitude
- Geo Container Longitude


### Distillation

Apart from outlier cases, in general they all seem to have the
following:

- Raw data, often (but not always) in `original-data/`, in CSV format.
- A master makefile, typically `csv.mk`, which coordinates the normalisation.
- Config, defined in `common.mk`, with development/production
  specifics in `editions/*.mk`
- Scripts, often (but not always, and not only) `converter.rb`
- `css/` containing HTML stylesheets

Sometimes, there are also:
- SPARQL queries
- Documentation
- Cached / intermediate data

Clearly, a maintenance problem has arisen from the emerging practice
of cutting and pasting an existing project to creating each new one,
and then tweaking it.  This has led to much duplication, which
obscures what is common, or more relevantly, different about each
case.  The old scripts sit around cluttering up the source code. And
the data is checked into the repository too - likewise, I not sure if
this a maintainable way to keep it.

The makefiles define a lot of variables, and the stitching together of
these obscures what is actually going on.

Another issue is the somewhat complex commands the user is expected to
run in sequence to process the data.  There are quite a lot of paths
to remember, and parameters to supply. More than seems necessary -
getting anything to work at all is a bit of a challenge at first.

## Conclusions

I think Dean has made a good move in replacing the Makefiles with Ruby
scripts. I think this needs to be taken further, and the amount of
boilerplate being cut and pasted reduced to an absolute minimum.

Old data schema should be removed when no longer in use, and preserved
only in version control history.

The raw/intermediate/final data itself might want to be stored
elsewhere, version controlled, perhaps as part of a deployed system
snapshot?

We need a way to adjust the builds for live or development versions of
perma-ID URIs such as purl, w3id, and lod.coop, simply.

[README.md]: ./README.md
[CSV_MAPPING.md]: ../tools/se_open_data/CSV_MAPPING.md

# Colophon

Initially written May 2020, Nick Stokoe.
