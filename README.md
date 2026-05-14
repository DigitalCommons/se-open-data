# The se-open-data Gem

This Ruby Gem defines a framework and some utilities for fetching,
normalising and publishing third party datasets of varying quality,
such that downstream users or processes can consume the data in a
regularised, consistent, high-quality form.

Specifically, it aims to supply [Five Star] grade [Linked Open
Data][LOD]. Also, three and four star data is generated en-route and
published in addition. See the linked definition of [Linked Open
Data][LOD] for an explanation of what these grades mean.

It supports doing this both manually via the command-line, and
scheduled automatically as a service.

The key thing this Gem includes are is a command-line interface `seod`
(amongst some others detailed below).

Plus, to aid with the implementation of the conversion, classes for:
- config-file parsing
- [CSV] (Comma Separated Values) file specification and transformation
- Data validation and normalisation
- [SKOS] vocab retrieval and management
- [Geocoding][geocoding] addresses
- Re-publishing that data as static files and [SPARQL] queriable data.

> [!NOTE]
>
> This is a Digital Commons Cooperative project. Please follow the
> [contribution guidelines] if you wish to participate.

## Synopsis

The general use-case is, conceptually:

- create a directory for your conversion project;
- install the gem;
- implement your converter script (and add any ancillary files!);
- put your input data into the correct file, if necessary; and finally
- run `seod` with the required parameters.

## Where to start

What I would suggest you do next, having read the documentation up to
here.

- If you want a conceptual understanding, go to the
  [Framework](#The-Framework) section.
- If you want to try a practical example:
  - Check you have the necessary [Prerequisites](#Prerequisites)
  - Then go to the [Example use case](#Example-use-case) section and
    follow that.

There are some concepts you need to understand in order to use this
Gem, but you should be able to execute the example without much more
than a basic knowledge or Linux and Ruby.

## Prerequisites

Ruby 3.x or higher, the [Ruby Bundler] tool.

The [Password Store] command needs to be installed and configured to
use a pre-initialised store containing the API keys or passwords
needed to access external services.

The [`ssh`][ssh] CLI tool is typically assumed to be used for
deploying data, with keys associated by your `ssh` configuration in
`~/.ssh/config`, although this can be disabled by the config (and
`seod` CLI options).


## Example use-case

A very brief example follows to give an overview. The set-up is in the
form of shell commands you can paste into a terminal, so you can try
this out easily. The commands create all the files for a small working
example.

### Set up your project

First, define TAG and PROJECT to specify the name of the folder, and
the version of this gem to use.

    TAG=v2.5.1
    PROJECT=dummy

You can then paste the following set-up code into a terminal:

    mkdir -p ${PROJECT?}; cd $PROJECT

    bundle init
    bundle config set --local path .gems
    bundle add --github=DigitalCommons/se-open-data --ref=${TAG?} se_open_data

    # Define the input schema ##################################################
    cat <<EOF >schema.csv
    id,header,description,comment,primary
    id,Membership #,,,TRUE
    title,Title,,,FALSE
    street,Street Address (HQ),,,FALSE
    city,Town/City (HQ),,,FALSE
    websites,Home Page,,,FALSE
    EOF


    # Define the output schema #################################################
    cat <<EOF >output.csv
    id,header,description,comment,primary
    id,Identifier,,,TRUE
    name,Name,,,FALSE
    address,Address,,,FALSE
    urls,URLS,,,FALSE
    EOF


    # Define this minimal config ###############################################
    # Mostly parameters required for config to be valid.
    # (Note the use of PROJECT)
    cat <<EOF >default.conf
    # For convenince, load data from current directory
    SRC_CSV_DIR = .

    # Used for generate step; typical development values.
    URI_HOST = dev.lod.coop
    URI_PATH_PREFIX = $PROJECT
    ESSGLOBAL_URI = https://dev.lod.coop/essglobal/2.1/

    # Used for deploy step (adjust for your case)
    DEPLOYMENT_WEBROOT = ./out-www

    # Used for triplestore step (adjust for your case)
    VIRTUOSO_ROOT_DATA_DIR = ./out-ts
    SPARQL_ENDPOINT = https://example.com
    VIRTUOSO_PASS_FILE = dummy.password
    EOF

    # Create a simple input CSV ################################################
    cat <<EOF >original.csv
    Membership #,Title,Street Address (HQ),Town/City (HQ),Home Page
    aaa,Apple Co-op,"1 Apple Way",Appleton,http://apple.coop
    bbb,Banana Co,"1 Banana Boulevard",Skinningdale,http://banana.com
    ccc,The Cabbage Collective,"2 Cabbage Close",Caulfield,http://cabbage.coop;http://cabbage.com
    ddd,The Chateau,,,
    EOF

    # Define the `converter` script ############################################
    cat <<EOF >converter
    #!/bin/env ruby
    require 'se_open_data/setup'
    require 'se_open_data/csv/schema/types'

    class Observer < SeOpenData::CSV::Schema::Observer
      T = SeOpenData::CSV::Schema::Types

      def initialize(setup:)
      end

      def on_row(id:, title:, websites:, street:, city:)
        # preserve id field, transform the other fields
        yield id: id,
          name: title.capitalize,
          urls: T.multivalue(websites) {|it| T.normalise_url(it, default: nil) },
          address: T.normalise_addr(street, city, 'United Kingdom')
      end
    end

    SeOpenData::Setup.new.convert_with(observer: Observer)
    EOF


    # Make sure the scripts are executable: ####################################
    chmod +x converter

### Invoke the seod command

Having set this up successfully, you can use `seod` command.

> [!TIP]
>
> The commands here assume the Gem's executables and source code are
> in the shell's executable path / Ruby's include path,
> respectively. The simplest way to arrange that is to run the
> following command in your terminal first. This will spawn a
> sub-shell set with the correct environment variables for subsequent
> commands to have these set correctly:
>
>     bundle exec $SHELL
>
> Alternatively, prefix each command with `bundle exec`, as in this
> example:
>
>     bundle exec seod convert

To convert `original.csv` into your target format [CSV], by default
`generated-data/standard.csv`, run:

    seod convert

To generate the HTML, [RDF] and [TTL] files:

    seod generate

Look in `generated-data/` - you'll find:
- the converted CSV `standard.csv`,
- the static files in `www/`,
- triple-store importable data in `virtuoso/`
- and some data in `csv/` and `sparql/`, which you can typically ignore.

Next, to deploy that data in the file-system, or on a web server (as
per the configuration), you would typically run the following command.

> [!WARNING]
>
> However, the settings created above will need to be amended for your
> case before the following command will work.
>
> Unfortunately, explaining that is outside the scope of this short
> example. See the sections explaining the configuration with a longer
> example below.

    seod deploy

Finally, to import it into a [Virtuoso] database, you would run:

    seod triplestore

*(Again, likely this won't work without modification and access)*

## The Framework

### Input Data

Historically these datasets have been lists of Co-operatives,
organisations, or other "initiatives" in the "[Solidarity Economy]"
(hence the name). *However, they need not be limited to that.*

**The main assumption is that it is logically possible to extract a
list of items which have, at minimum, the following attributes:**

- A unique, stable identifier.
  - *Unique*, meaning, used only for one item in a given dataset.
  - *Stable*, meaning, it can be relied on to consistently represent
    the same item throughout successive editions of the dataset.
- A name.
  - Meaning, a short, human readable label for this entity.
  - This need not be unique or stable, but would ideally be unique.
- (Ideally) a [geocodable][geocoding] address or location coordinates.
  - Meaning, something indicating where this item should appear on a
    map.
  - This is optional, since some items won't have a physical location,
    or at least not a known one.
  - This is preferably a coordinate, but an address is often all we
    can get.
  - Addresses are however, difficult and unreliable ways to infer
    a location...
  - And, there is also an implicit assumption that there is only *one*
    location.

If these core attributes are not available, things become difficult.

For instance, a identifier can be invented *post-hoc* on receipt of
the dataset, but without the cooperation of whoever is maintaining and
supplying that dataset, it will not be reliably consistent, and
maintaining consistency will impose a lot of effort on the receiver.
If that happens, it amounts to conceding that the receiver has now
assumed burden of, and *the authority for* maintaining the data.

Also, names and locations can't easily be inferred without having
something semantically close in form.

With respect to the other attributes of the dataset items: there are
no specific assumptions, except that:

- They are expected to vary from dataset to dataset, but
- Remain consistent between successive editions of the dataset.
- Remain fairly consistent from item to item (depending on the attribute).

Factors which need to be considered when interpreting the source data
are:

- Multiplicity: single- versus multiply-valued.
- Variability: enumerated (i.e. possible to represent with [SKOS]
  vocabulary terms) versus
  unconstrained values (typically plain text, possibly interpreted as
  numbers, dates, or other values).
- Optionality: required versus optional values.
- Types (e.g. numbers, text, booleans, dates, etc.) Different formats
  support different types to varying degrees of explicitness.
- Locality: text values can be in different languages, and even numbers
  and dates can have localised forms (especially currency)
- Character Encoding - these are often implicit, and using the wrong
  one can result in [mojibake].
- Format: a variety of these are used, ranging from comma delimited
  values, tab (or other) delimited values, various types of [JSON],
  various kinds of spreadsheet, and other, sometimes custom
  formats. These all come with their own support for, and limitations
  in semantics.
- Delivery: the data can come via email, files over HTTP or FTP,
  various custom APIs, etc.

A custom conversion process is therefore almost always required,
except where datasets deliberately share the same data format and
semantics, which is rare.

But of all input formats, CSV is probably the simplest to deal with,
and one of the most common in practice.


### Output Data

The output of the process are:

- Normalised [CSV]s (three star [Linked Open Data][LOD])
- Static HTML, [RDF] and [TTL] data files (four star [Linked Open Data][LOD])
- Linked data graphs stored in a [Virtuoso] [triple-store] database,
  queriable with [SPARQL] (five star [Linked Open Data][LOD])

The deployment and import of that data *can be* executed as part of the
process.

The original aspiration was to create [Five Star] [Linked Open Data][LOD],
i.e. linked open data queriable using [SPARQL]. Indeed all the
datasets here currently can generate that - but also four star ([RDF],
[TTL]) and three star ([CSV], and HTML) data.

> [!NOTE]
>
> So far, most downstream uses have stopped at three star data,
> including the [MykoMap] project, which consumes CSV and transforms
> this into a convenient internal format. Partly this is because the
> higher grades of data representation impose a higher cognitive
> burden on the user, and more sophisticated tools to manage and
> interpret.

The foundational output data is in the form of a CSV file. The default
name for this is `standard.csv`.

From this file, static data is generated for publishing online
(including the CSV itself).

Similarly as for the input data, there are often some implicit
semantics to be navigated, on top of the CSV format. 

In our case we:

- Support the usual CSV escaping scheme for quotes by doubling it
- Support multiple values encoded in fields, using a second delimiter
  and an escaping scheme to permit the delimiter to be included in
  values. (Usually a semicolon, and backslash escaping as used in JSON
  strings).
- All fields have a semantics which depends on the field.
- Can sometimes be inconsistent in our encoding of SKOS vocabulary
  terms.
  
Our SKOS representation has been inconsistent in the sense that we
have used all of:
- The full URI - which means development and production data use a
  different host-name specifier, resulting in distinct for URIs for
  the same term.
- Just the identifier (which assumes only one SKOS vocab is in play)
- A [QName] - an abbreviated form of an URI which collapses the common
  base URI into a predefined tag, usually with two characters. (This
  is probably the most preferable form as it avoids most of the
  problems of the alternatives.)
- The text label (which is frequently localised, possibly
  inconsistently). This should be avoided, since spelling errors can
  creep in, and these labels are not guaranteed to be stable or
  unique. But frequently this is how our sources send us vocabulary
  terms, even if they have database-based software (e.g. a Customer
  Relationship Manager AKA a CRM) which uses identifiers internally.

Localisation is only partially supported by our CSV format.  In that
it can be supported when a field is enumerated, insofar as the SKOS
vocabulary representing them supports that. This is a strength of
using SKOS (or something akin to SKOS, like our `vocab.json` files).

However, unconstrained text values cannot be, and their precise
interpretation is implicit. The workaround for localisation is to
include as many text fields as there are languages for those
unconstrained text values which need to be localised.

The "CSV schemas" used by this gem helps to tackle this problem of
interpretation by a) defining and enforcing the expected headers, and
b) allowing their semantics to be documented, at least. More could be
done, but that would require a more complex schema definition.

The formats of static data currently published are: HTML, [RDF],
[TTL], and [CSV], although other formats can be published with some
customisation. Support for the [Murmurations] distributed index API
has been added more recently.

Also, an [RDF] dump suitable for importing into a [triple-store]
(assumed to be [Virtuoso]) is generated.

In all cases, assumptions have to made about the semantics when
interpreting the output `standard.csv` file and re-encoding it in a
different format, and historically these were frequently hardwired
into the code for generating the linked data. 

> [!WARNING]
> 
> This makes the RDF generation process particularly brittle when the
> data schema differs significantly from the original one assumed by
> the "Solidarity Economy Initiatives" schema (see [The built-in CSV
> schemas](#The-built-in-CSV-schemas) below.) When that happens, the
> most expedient thing to do is to skip the later steps of the process
> following the `convert` step entirely. The code needs to be
> refactored for more flexible behaviour to support RDF output in the
> general case.
>
> For the use-case of MykoMap data, stopping with the `standard.csv`
> is often not so much of a problem, since it starts from the
> `standard.csv`, and has its own means of defining how the CSV fields
> should be interpreted.

> [!WARNING]
>
> One thing to note about the SKOS vocabs is that their full URIs are
> typically long. Usually [QNames][QName] are used to define
> abbreviated forms. This also allows some isolation of the data
> development/production forms of URIs

### Manual vs automatic execution

The normalisation processes can be invoked:

- Manually by the user, with interaction via the console. 
  - *(This is the typical case for datasets which cannot be obtained
    online, needing to be downloaded / extracted and potentially
    inspected before conversion)*
- Automatically by a non-interactive process.
  - *(This is the typical case for datasets which can be obtained
    online in a high-quality form which does not need manual oversight
    to process)*

The former use-case is useful for diagnostics and development. The
latter is better for bulk-processing data - but assumes reliably
consistent data can be obtained.


### Historical background

The origin of this software began when the [Solidarity Economy
Association][SEA] started mapping the [Social and Solidarity
Economy][SSE] with the "SEA Map" project. Lists of organisations would
be gathered at face-to-face events called "map jams", and curators
would subsequently maintain and add more using a
questionnaire. Originally the [Lime Survey] tool was used.

The SEA adopted the [ESSGLOBAL] Semantic Web ontology to classify these
organisation, which was the result of earlier work by Mariana Curado
Malta circa 2014, and published by [RIPESS], a global network
committed to the promotion of the [Social Solidarity Economy][SSE].

- A PhD thesis: "A methodological contribution to the development of
  metadata application profiles in the context of the Semantic Web."
  [1]; also,
- A paper "Social and Solidarity Economy Web Information Systems:
  State of the Art and an Interoperability Framework" [2].

It included a set of [SKOS] Vocabularies defining terms intended to
represent various attributes of these SSE "initiatives". For instance,
their structural organisation, legal forms, economic activities, and
membership structure.

> [!NOTE]
>
> The term "vocabulary" will be used for the most part here to mean
> [SKOS] Vocabularies, although "taxonomy" is more frequently used for
> the same idea in other fields.

> [!NOTE]
>
> Throughout the Sea Map project, now renamed as "MykoMaps", the
> entities represented by the data were referred to generically as
> "initiatives". This still survives in the source, although more
> recently the term is the more generic one, "data items", so as not
> to prejudice its use as being only for SSE initiatives.

When RIPESS appeared to be no longer maintaining ESSGLOBAL, the SEA
took on the role of maintainer on so it could continue using it, and
with the intention of promoting it for use by others.

In order for suitable map data to be generated, the externally
maintained data needed to be downloaded, normalised and annotated with
vocabulary terms, and addresses [geocoded][geocoding] (AKA geolocated). Then
this could be used to create linked open data for a) publishing
online, b) querying via a SPARQL endpoint, and c) transformed into
online maps.

The use of Semantic Web technology was intended facilitate open-source
data mash-ups using this and other datasets. Technology such as [RDF]
(a framework for describing concepts and relationships, with a family
of representation languages), [Virtuoso] (an open-source triple-store
graph database), and [SPARQL] (a W3C standard for Semantic Web
queries) were expected (at that time) to constitute a more modern,
world-wide-web friendly alternative to the more conventional
relational databases, [SQL] (Structured Query Language) queries, and
suchlike.

This was explained in a presentation for the [Open:2017] conference,
"Linked open data for the Solidarity Economy" *(description, slides
[3]; video [4])*.

> [!TIP]
>
> A good primer on Semantic Web Technology is "The Semantic Web for
> the Working Ontologist", by Allemang, Dean, Hendler, James Jim
> Hendler, available online [5]
> 
> The Semantic Web lives on, although has lost the favour it used to
> have in academic circles, and especially in industry. This has led to
> many Semantic Web tools becoming unmaintained.
> 
> See this review of "The Semantic Web, Two Decades On" [6].


### The original implementation

This gem replaced an original combination of Ruby scripts and
Makefiles created by Mat Wallis, and maintained until
circa 2020. These downloaded the aforementioned external data sets,
normalised them into a standard [CSV] file format, added ESSGLOBAL
vocabularies, then transformed the normalised CSV files into linked
open data and HTML formats for publication.

Static files were publicised on the web, and "graphs" of linked data
were imported into a Virtuoso [triple-store] database for querying
using [SPARQL].

The data was conceptually assumed to be a list of records representing
the "initiatives", or organisations, typically with a name,
description, a physical address, contact details, possibly a location,
website, nationality, and other details, depending on the source.

External data was converted to use standard set of fields, which could
be represented by a CSV with standard headers - usually called
`standard.csv` or the "Standard CSV format" here, for want of a better
name. 

> [!NOTE]
>
> In the code it is referred to "Lime Survey Core" as it was derived
> from the CSV exported from the original [Lime Survey] questionnaires.

The scripts and Makefiles were embedded in a single project, with a
directory for each dataset.  Relative paths were used to refer to
common files.

However, in practice these Makefiles got quite complicated to set up
and use. Whilst being able to use file timestamps to detect when
intermediates are newer than their sources, allowing build steps to be
skipped, the cognitive overhead of their use and maintenance seemed to
rather outweighed this benefit (at least to the author of this Gem.)

### How this has changed

To reduce the complexity of maintenance, the Makefiles were removed in
favour of a linear series of steps executed in turn, plus a key/value
text configuration file instead of Makefile variables (with similar
but simpler syntax).

The `open-data` repository was created to contain the various data
projects and their specifics, whilst the common code was decoupled
from the data by splitting it out into this gem. The data projects
import it directly from its repository on GitHub.

A single main script `seod` provides a command-line interface which
can be used to invoke the steps of generating data. (The script gets
its name from "Solidarity Economy Open Data".)

The steps supported by `seod` follow the same sequence of the build
targets in the Makefiles. However, they are invoked in sequence, with
no timestamp detection.

The old Ruby scripts, each with their own command-line parameters,
could then be replaced with an API implemented in Ruby and invoked
directly. This reduced the amount of boilerplate code, increased
sharing, and was far more unit-testable.


### The current form of the framework

Conceptually, the data undergoes the same transformations as
before. However,

- The form of the CSV files (input and output) is defined declaratively.
  - A "schema file" is used to define this (see below).
- An optional `downloader` script can be supplied.
  - This is invoked to (ideally) detect when the original data has
    changed, and fetch that.
- A mandatory `converter` script is required.
  - This is invoked to perform the normalisation from original data.
- Other tools are provided to validate data, geocode addresses, map
  vocabularies and capture them as JSON / CSV.

> [!WARNING]
>
> Unfortunately there are places where the old code has not been
> refactored and is still complex and/or murky. Especially with respect
> to linked data generation, and to some extent to geolocation.


#### The transformation steps

Overall, these steps are:

- **download**: retrieve the raw data from somewhere online
- **convert**: validate and normalise the raw data,
  creating a CSV version (typically called `standard.csv`)
- **generate**: transform the normalised data into a standard set of
  publishable formats
  - HTML: an `index.html`, linking to an HTML file per initiative
  - [RDF/XML]: an `index.rdf`, linking to an RDF file per initiative
  - [TTL]: an `index.ttl`, linking to a TTL file per initiative
  - `meta.json`: contains timestamps, digests, Git commit IDs
    and other information describing the build
  - `standard.csv`: the normalised dataset
- **deploy**: publish the previously generated static files online
- **triplestore**: import the previously generated graph data into Virtuoso

These correspond to sub-commands of the `seod` script. Run `seod` with
no arguments to output some help about these and their allowed
parameters.

There are other sub-commands - notably **run_all**, which runs all of
the above in sequence, stopping on success or a failure.

Some of the above steps can (or must) be customised using scripts in the
project directory, as follows:

- **downloader**: this can be omitted, but if present is invoked to
  get external data.
  - The downloaded data is expected to be written as a file defined by
    the parameter ORIGINAL_CSV, and in the directory defined by
    SRC_CSV_DIR.
  - These parameters default to `original.csv` and `original-data` respectively.
  - The return code indicates either success (0); no download (100),
    meaning the data is known to be already up to date (100); or
    failure (anything else).
- **converter**: this script *must* be present.
  - It is expected to output a CSV file defined by the configuration
    parameter STANDARD_CSV in the directory TOP_OUTPUT_DIR
  - These default to `standard.csv` and `generated-data`
    respectively.
- **generator**: if present, this overrides the default generator
  step.
  - It is assumed to perform something loosely equivalent such
    that following steps can run.
  - If absent, the default implementation reads the STANDARD_CSV file
    and generates the various static files and RDF data dumps listed
    above.
- **post_success**: if present, this is invoked on a successful
  sequence.
  - It can be used for notification, or to perform custom steps,
    perhaps for deployment.

These scripts must be executable. They should return zero on success,
non-zero on error. Thus they can *in principle* be
implemented with anything you like - bash, C++, Javascript, etc.

However in practice I'd recommend using Ruby: this the path of least
resistance. You then don't need to re-implement things such as
configuration file parsing, behaviour will be consistent, and your
code focused on those specifics needed for a given case.

Ruby is also a very flexible but succinct language with a lot of
library support.


#### CSV fields

The input and output fields defined for the initiatives can vary
between datasets. However, the bare minimum is:

- An ID field, stable over time, and unique to the dataset.
- A name field.

This ID is essential in order to be able to identify the same entity
in the dataset as it evolves. Uniqueness is enforced by the framework.

The name is essential to label the item in human-readable contexts,
and should be unique (but this is not enforced).

Also highly important for the intended purpose of mapping:

- A geographic latitude/longitude location, and/or
- An address which can be geocoded to such a geographic location

These can be absent, but if so will result in the item appearing in
lists, but excluded from any maps.

And typically, when geocoding addresses, we also include:

- A percentage "confidence" indicator from the geocoder, when available.
- The actual address geocoded.
- A "geocontainer", which is a valid URI that the linked data can use
  to uniquely represent the location.

The confidence is useful to spot bad geocoding - this typically gives
a hint that the address is bad in some way.

The original address may have been cleaned up, and combined from
several fields in various possible ways. Therefore being able to
inspect the actual address used for geocoding is important to
replicate the problem and understand why the geocoding failed.

The "geocontainer" field is primarily needed because in practice the
legacy linked data generation code won't work correctly without
it. However, it can be an opaque URI, and therefore arbitrary. Open
Street Map URLs are typically used for convenience, as these can also
be used to visualise the location. (This gem provides a way to
generate those from latitude/longitude pairs, see the #osm_uri method
of the SeOpenData::Geocoding::Result class)


#### CSV Schemas

CSVs aren't usually described as having "schemas" but we borrow the
concept to encapsulate the idea of:

- What headers we expect (at minimum)
- Which of those are the "unique identifier" (this is then enforced
  unique)
- What tag to use to represent them in code
- Optionally, a description and a comment for documentation purposes.

These schema definitions therefore allow CSV files to be validated
using a standardised process, and help bridge the often unwieldy
naming used in CSV files (containing capitals, punctuation and spaces)
to Ruby symbols (lower-case alphanumeric tags).

The original schema format used YAML, for readability. It included a
comment and description for the schema as a whole.

An example of what this looks like:

```
---
id: :my-dataset-id
name: My Dataset Name
version: 20220921 # can be anything lexically sortable, but typically a date
primary_key:  # this identifies the fields which uniquely identify a row
- :record_id
# Comment is optional
comment:
fields:
- id: :record_id
  header: Record ID
  desc: A unique identifier for organisation
  comment: ''
- id: :address
  header: Address
  desc:
  comment:
# ...etc. more fields here
```

Later, support for a CSV version was added for rapidity of
construction. This was useful when a large number of datasets landed
and needed to be integrated into the pipeline rapidly. The columns for
per-field descriptions and comments were included, but the schema
description was dropped.

An example of the same schema in CSV format:

```
id,header,description,comment,primary
record_id,Record ID,,,,TRUE
address,Address,,,FALSE
<...more fields here ...>
```

> [!TIP]
>
> CLI tools for converting between these two exist in the `bin/` folder.

#### The built-in CSV schemas

There is a built-in CSV schema we know informally as the "standard CSV
schema" (more officially called "Solidarity Economy Initiatives"
schema). This historically was the standard CSV *output* schema. It
evolved, so there are several versions of it, identified by index
numbers. (See SeOpenData::CSV::Schemas.)

However, as more recent datasets have become more diverse,
supplementary fields became commonplace. So although this schema is
still used as a base schema, usually there are some extra fields
included to cater to the often unique data fields for specific
datasets.

For these, the usual pattern is to include an `output.csv` or
`output.yml` file, which contains a copy of the core "Solidarity
Economy Initiatives" schema with the required additions appended.

For cases where no extra fields are required, no such file is needed,
as the built-in schema can be used. This is increasingly rare.

Additionally, many of the fields of the standard schema are also
increasingly left empty and unused.

Another built-in CSV schema called "LimeSurvey Core" was created later
(see SeOpenData::CSV::Schemas::LimeSurveyCore). This was an *input*
CSV schema to eliminate duplication in the older projects that were
using Lime Survey and shared the same input schema.

You can read more documentation inline in `se_open_data/csv/schemas.rb`.


### Configuration files

These are text files which define parameters that all scripts can read
by calling `SeOpenData::Config.load`.

When using the SeOpenData::CSV::Schema::Observer class as a base for
your converter script (which is recommended), the configuration is
loaded for you and the constructor will receive a SeOpenData::Config
instance in the `setup` parameter. (See `se_open_data/setup.rb` for
inline documentation; TL;DR: use the `#config` method.)

These configuration files support comments, prefixed with a `#`
character.

Empty lines are ignored.

Configuration parameters are defined by an alphanumeric (plus
underscore) label, followed by an `=` symbol (both optionally padded
with white-space on each side), then some text.  White-space at the
end of the line is also ignored.

For instance:

    # This is a comment
    ANIMAL = cat
    VEGETABLE = turnip

There is no prohibition for arbitrary parameters - you can add them
and the parser will include them in the resulting config hash.

However, the config parser *requires* certain parameters to be set,
and will complain if they are absent. It will also define certain
defaults for other expected, but absent, parameters.

For full details, see `se_open_data/setup.rb`


### Converters

The most recent converter API uses the "observer" pattern: a subclass
of the SeOpenData::CSV::Schema::Observer class is supplied by the
user, defining methods which act as call-backs representing certain
events in the conversion. Optionally, there is one called for the
header row, then another is called for each data row.

Using this with CSV schema definitions aid succinct, readable code. In
the simple case the observer class only needs to implement a single
method, #on_row.

This #on_row method accepts a row of data via keyword parameters, as
defined by the input schema.

It can then emit zero or more rows by calling the `#yield` method.
Similar to #on_row, this takes keyword parameters. However these are
defined by the *output* CSV schema, and mapped to output CSV headers.

Validation that the required columns exist in both cases is performed
by the framework, which also loads the schema definition files if they
use the standard names.

However it is implemented, the expected output of any converter script
is a CSV file, by default called `standard.csv`. Although that can be
changed with the configuration parameter STANDARD_CSV.

This CSV file is consumed by all the following steps in the
transformation process.


#### Downloaders, Generators, On Success

As mentioned, these scripts can also be supplied, but are
optional. More details can be had in the following examples.


### A longer step-through example

Make sure you have the prerequisites installed (see above).

#### Create a Gemfile and configure Bundler

Create a folder for a new Ruby project. Usually it's named after the
dataset ID in question. We'll assume the ID is `nonesuch`, and name it
accordingly:

    mkdir nonesuch
    cd nonesuch

Add a Gemfile:

    source "https://rubygems.org"
    gem "se_open_data", :github => "DigitalCommons/se-open-data", :tag => "YOUR.VERSION.HERE"

Amend the string `YOUR.VERSION.HERE` here to reference the git tag on this
repository you want to use - these are used for marking releases. (See
["Releasing"](#Releasing) below.) The `:github` tag defines the git
repository to obtain it from - see Ruby's documentation for the
`Gemfile` format for full information about these tags.

Optionally, you can add any other gems you need for your scripting.

Usually, next we tell Bundler to install its Gems locally to our
project, to avoid it trying to do that in a system directory. A common
way to do that is to add a `.bundle/config` file (often copied from
another project):

    ---
    BUNDLE_PATH: ".gems"
    BUNDLE_BIN: ".gems/bin"
    BUNDLE_GLOBAL_GEM_CACHE: "true"
    BUNDLE_CACHE_ALL: "true"
    BUNDLE_NO_INSTALL: "true"
    BUNDLE_CACHE_PATH: "../caches/gems"

The settings for `BUNDLE_BIN` and `BUNDLE_CACHE_PATH` can be anything
you like, but make sure they exist and are (initially) empty.

#### Install the gem

    bundle install

This should download and fetch this gem, and all its dependencies.

You should now be able to run the `seod` command: - running it with no
arguments will get some help.

    bundle exec seod

#### (Optionally) create a downloader script

A trivial non-Ruby example follows, to show it can be done:

    curl https://example.com/data.csv > original.csv

(In general you will want to use Ruby, as in the short example that
follows below.)

Make sure it's executable:

    chmod +x downloader

The general expectation is that it will downloaded from the URL
defined by the config parameter DOWNLOAD_URL. Our toy example
hard-wires that assumption, which is generally bad form.

The following example uses some standard SeOpenData download logic,
which loads the configuration automatically.

That logic first checks with a HTTP HEAD query to see if the ETAG
header of the content at DOWNLOAD_URL matches the last one seen
(stored in a file named after ORIGINAL_CSV with the `.etag` suffix).
If it does, it will exit with return code 100. Otherwise it will
download the content at DOWNLOAD_URL into STANDARD_CSV with a HTTP GET
query, save the updated ETAG for next time, and exit with return code
0.

    #!/usr/bin/env ruby
    require 'se_open_data/cli'

    # Run the entry point if we're invoked as a script.  This just does
    # the csv download. But we also exit with the returned value, to
    # signal whether it succeeded (return code 0 or true), failed (1 or
    # false), or was just skipped because there is no new data (return
    # code 100)
    #
    # For the purpose of this script
    # @see SeOpenData::Cli#command_http_download
    exit SeOpenData::Cli.command_http_download if __FILE__ == $0

However, you can write whatever you like in this script, so it can do
something arbitrarily complicated. Extra API keys or parameters can be
loaded from the config object as required.

> [!TIP]
>
> A current example of something more complicated is that in the
> `coops-uk` dataset in the `open-data` project. This attempts to
> infer the DOWNLOAD_URL, which changes month to month, by scraping
> their website.

#### Create your schema definitions

Although you don't really need to with the toy converter below, if you
plan to use the observer class pattern mentioned above you *will* need
schema definition files.

The input schema file is expected to be called `schema.yml` or
`schema.csv`, and the output `output.yml` or `output.csv`.

Here's an example input schema, which defines some fields, and labels
one as the primary key (with TRUE), meaning that the values in it must
have no duplicates.

    id,header,description,comment,primary
    id,Unique ID,,,TRUE
    organisation_name,Organisation Name,,,FALSE
    address,Address,,,FALSE
    website,Website,,,FALSE
    acme_code,ACME Code,,,FALSE

An example output schema definition follows. If this is absent, the
output schema defaults to the latest standard "Solidarity Economy
Initiatives" schema (see `lib/se_open_data/csv/schemas.rb`).

This schema is a cut-down version of that, with one extra header
called "ACME Code".

    id,header,description,comment,primary
    id,Identifier,,,true
    name,Name,,,false
    description,Description,,,false
    homepage,Website,,,false
    latitude,Latitude,,,false
    longitude,Longitude,,,false
    geocontainer,Geo Container,,,false
    geocontainer_lat,Geo Container Latitude,,,false
    geocontainer_lon,Geo Container Longitude,,,false
    geocontainer_confidence,Geo Container Confidence,,,false
    geocoded_addr,Geocoded Address,,,false
    acme_code,ACME Code,,,false


#### Create a converter script

A `converter` script is required. It will be used to perform the
`convert` step, and must be executable.

Again, the implementation is up to you. This is a non-Ruby toy example
which only strips blank lines:

    egrep -v '^ *$' original.csv > standard.csv

Then, this example is a less toy-like version uses the Observer class
to take the schemas above and map one to the other, with some basic
normalisation/validation and geocoding:

    require 'se_open_data/setup'
    require 'se_open_data/csv/schema/types'
    require 'se_open_data/lookup'

    # A class which defines callback methods #on_header, #on_row, and #on_end,
    # that are called during the conversion process.
    class Observer < SeOpenData::CSV::Schema::Observer
      Types = SeOpenData::CSV::Schema::Types

      # Set up anything persistent you need here
      def initialize(setup:)
        super()

        # Create a geocoder; assumes GEOCODER_API_KEY_PATH is defined
        # in the config
        @geocoder = setup.geocoder

      end

      def url(text)
        Types.normalise_url(text, throw: true)
      end

      # Called with an array of header fields, and a field_map, which
      # is an array of integers denoting the schema index for each header
      def on_header(header:, field_map:)
        @ix = 0 # initialise a row counter
      end

      def on_row(
            # These parameters match source schema field ids
            id:,
            organisation_name:,
            address:,
            website:,
            acme_code:
          )

        @ix += 1 # increment the row counter
		# warn "processing row #{@id}"  # a diagnostic
		
        # Examples of common conversion steps:
        addr = Types.normalise_addr(address)
        geocoded = @geocoder.call(addr)

        # The paramters below are assigned with the actual values to write.
        # You may yield zero or many times if desired, and the equivalent number
        # of rows will be emitted.
        yield id: id,
              name: organisation_name,
              description: nil,
              homepage: url(website),
              latitude: nil,
              longitude: nil,
              geocontainer: geocoded&.osm_uri,
              geocontainer_lat: geocoded&.lat,
              geocontainer_lon: geocoded&.lng,
              geocontainer_confidence: geocoded&.confidence,
              geocoded_addr: addr,
              acme_code: acme_code

      end

      # Called after all the rows have been processed
      def on_end
      end

    end

    SeOpenData::Setup
      .new
      .convert_with(observer: Observer)

#### Create a config file and (optionally) a generator script

Currently, you also need to create a config file for `seod`.

`default.conf` is the usual name for this, but `local.conf` will be
used in preference if it exists: this is to support development
configurations - usually `local.conf` should not ever be checked
in. The environment variable `SEOD_CONFIG` can be set to the name of a
different config if that is needed (perhaps for different build
scenarios).

(See the inline documentation for `se_open_data/config.rb` for more detail.)

The default `generate` step does need some configuration; *however* if
you define an empty `generator` script, this can be skipped and your
config can be empty.

For example, a bare-bones `generator` script just needs to (re-)create
TOP_OUTPUT_DIR and put the STANDARD_CSV file in there. This assumes
these config variables are the defaults, `generated-data` and
`standard.csv`.

    mkdir -p generated-data
    cp standard.csv generated-data

But if you *don't* override that generate step, you'll need a bunch of
mandatory configuration parameters - not all of which are needed for
this step, but are expected by the config parser currently. The bare
minimum is something like this:

    # These define how to get/interpret vocab definitions
    URI_HOST = dev.lod.coop
    URI_PATH_PREFIX = nonesuch
    ESSGLOBAL_URI = https://dev.lod.coop/essglobal/2.1/

    # If you use the Observer with a geocoder as above you will
    # need something like this:
    GEOCODER_API_KEY_PATH = mygeoapify.key

    # Not used by the generator step
    DEPLOYMENT_WEBROOT = /var/www
    VIRTUOSO_ROOT_DATA_DIR = /var/tmp/virtuoso/BulkLoading/
    SPARQL_ENDPOINT = https://example.com
    VIRTUOSO_PASS_FILE = dummy.password

The requirement remains because omitting these parameters are the
usual case. In practice, copying and amending a similar dataset's
config file has been the usual way to get something usable.

A more complete config such as you might find in existing datasets
follows. This example assumes:

- Our dataset ID is `nonesuch`
- Data comes as a downloadable CSV file from https://example.com/data.csv
- It will use the ESSGLOBAL v2.1 `activities-ica` vocab
- Of which we need the English and French localisations (`en fr`)
- We have a directory reserved for storing cache files in `../caches`
- And a key for the GeoAPIfy geocoding service in [Password Store] with the label `geoapify.key`
- The static data files should be published
  - via SSH on a host called `nonesuch.org`
  - under the path `/var/www/vhosts/nonesuch.org/www`
  - using log-in details defined in `~/.ssh/config` and
	`~/..ssh/authorized_keys` as usual.
- The RDF data should be published by bulk-import into a Virtuoso triplestore
  - on the host `ts.nonesuch.org`
  - via SSH to the temp path on the server `/var/tmp/virtuoso/BulkLoading/` (typical for Virtuoso),
  - and with a database password stored in [Password Store] with the label `ts.nonesuch.org.password`.

```
## se-open-data configuration
##
## Settings with single hash comments indicate config values assumed by
## default, override them if you need to. Other settings are (typically)
## mandatory, and you may need to adjust them for your case.

## Data will be loaded from <SRC_CSV_DIR>/<ORIGINAL_CSV>
## And output written below <TOP_OUTPUT_DIR>
# SRC_CSV_DIR = original-data
# ORIGINAL_CSV = original.csv
# TOP_OUTPUT_DIR = generated-data

## Set this if there is a download step that uses the stock downloader
DOWNLOAD_URL = https://example.com/data.csv

###########################################
## Components of the URIs used in this dataset:
## Generated URIs will start with: $(URI_SCHEME)://$(URI_HOST)/$(URI_PATH_PREFIX)
# URI_SCHEME = https
URI_HOST = dev.lod.coop
# URI_PATH_PREFIX =

## This defines the base URI defining the ESSGLOBAL version to use for vocabs.
ESSGLOBAL_URI = https://dev.lod.coop/essglobal/2.1/

###########################################
## Which linked-data vocabs to include in vocabs.json
## (used for MM 3.x - simply omit these if you don't need that,
## although this file can still be a useful component for building a config.json for
## MM 4.x)
VOCAB_URI_ACI = https://dev.lod.coop/essglobal/2.1/standard/activities-ica/
VOCAB_LANGS = en fr

###########################################
## Geodata cache - speeds up geocoding look-ups
GEODATA_CACHE = ../caches/filecache
GEOCODER_API_KEY_PATH = geoapify.key

###########################################
## To where are the Linked Data to be deployed?
##
## Note that content negotiation needs to be set up so that HTTP
## requests made to redirection URIs (URI_HOST etc.) can be
## dereferenced to the deployed RDF and HTML files (DEPLOYMENT_WEBROOT
## etc.)

## The value of DEPLOYMENT_SERVER should be the name of a host
## set up in an ssh config file. If omitted, deployment paths below
## are interpreted as local paths.
## DEPLOYMENT_SERVER = <rsync-server-url>

DEPLOYMENT_SERVER = nonesuch.org
DEPLOYMENT_WEBROOT = /var/www/vhosts/data.nonesuch.org/www
# DEPLOYMENT_WEB_USER = www-data
# DEPLOYMENT_WEB_GROUP = www-data

###########################################
## Triplestore deployment details
##
## The value of VIRTUOSO_SERVER should be the name of a host
## set up in an ssh config file. If omitted, deployment paths below
## are interpreted as local paths.
## VIRTUOSO_SERVER = <rsync-server-url>

VIRTUOSO_SERVER = ts.nonesuch.org
VIRTUOSO_ROOT_DATA_DIR = /var/tmp/virtuoso/BulkLoading/
# VIRTUOSO_USER = root
# VIRTUOSO_GROUP = root
SPARQL_ENDPOINT = http://ts.nonesuch.org:8890/sparql
VIRTUOSO_PASS_FILE = ts.nonsuch.org.password

# AUTO_LOAD_TRIPLETS = true

###########################################

## If this is false, only `pass` is used to look up passwords.
## Otherwise, the environment is checked first, then `pass`.
## Used when `pass` isn't available (i.e. when run via cron)
# USE_ENV_PASSWORDS = false
```

#### (Optionally) create a post_success script

This example will use `rsync` to publish the data to `nonesuch.org`'s web
root, under `demo`.

    rsync -rvz generated_data/ nonesuch.org:/var/www/demo/

#### (Advisedly) create a .gitignore file

You might also want to add a .gitignore to avoid checking in data and
other temporary files. For instance:

    /original-data/
    /generated-data/
    local.conf
    .gems

#### Run the scripts

Run all the steps with:

    bundle exec seod run_all

Although in practice will fail unless you've set the deployment config
variables correctly, which depends a bit on your set-up.

You can instead run each step you need manually:

    bundle exec seod download
    bundle exec seod convert
    bundle exec seod generate
    bundle exec seod deploy

The `open-data` project runs the former in a `cronjob` script, but
environment variables are used to override the defaults (which were
created for different needs) so that the conversion will run to
completion without needing to deploy files on other servers. See the
files in `tools/deploy/` for the implementation of that.

## Development

### Running against a development code-base

The normal mode is that the scripts in your data project run against
the gem installed in the bowels of the bundler's `.gem` folder
somewhere. You can in a pinch edit those files to insert trace logs,
or fix bugs, if you can get the path from an error message.

However, it's possible to instruct the Ruby bundler to instead use a
local directory (typically your Git working directory) as the Gem
source for your project. You can do this by adding a file in your home
directory called `~/.bundle/config`, if it doesn't exist, and make
sure it contains this parameter:

    ---
    BUNDLE_LOCAL__SE_OPEN_DATA: "/path/to/your/repository"

Note the double underscore.

Also note that that repository then must be checked out on the tag
named in your Gemfile (or alternatively a branch, if you use the
`:branch` symbol, or any ref at all if you use `:ref`). Amend the
Gemfile temporarily if you need to.

Then, proceed as normal with a `bundle install` etc. You should also
be able to debug the library using the Ruby debugger.

### Logging

There is a logging class included in se_open_data:
SeOpenData::Utils::LogFactory, found in
`se_open_data/utils/log_factory.rb`.

Documentation exists inline that module itself, but the main thing to
point out is that you can set the log level with the environment
variable SEA_LOG_LEVEL. For instance, this will change the log level
from the `warn` to `debug`, and show a lot more information when you
run `seod`:

    export SEA_LOG_LEVEL=debug

## Headless execution

Some hints for running `seod` within a cronjob or service, when an
interactive terminal is absent.

### Passwords

The command `pass` requires the user to enter a passphrase - so it
cannot be used to retrieve passwords when there is no interactive
console.

Therefore there is a configuration parameter USE_ENV_PASSWORDS, which
defaults to false, that can be set to true to short-circuit the use of
`pass`, and check the environment for variables defining passwords. If
they exist, those are used and `pass` is not invoked.

Password variables have the following format:

    PASSWORD__<normalised password store path>

Where `<normalised password store path>` is the Password Store path
(for instance `my/secret/api.key`), but upper-cased, and with
non-alphanumeric characters converted to underscores. So this would be
encoded as:

    PASSWORD__MY_SECRET_API_KEY

Therefore, in production you should set this configuration parameter
(typically by using the environment variable `SEOD_CONFIG` to define a
`seod` config file dedicated for production), and supply the necessary
passwords as environment variables. This should be part of the
deployment process.

Obviously, beware of using environment variables as they have their
own security problems.

### CLI parameters

When invoking `seod run_all` in a script, you can also use the
environment to supply default parameters to the sub-commands
executed. This is used to override the historical defaults when the
deployment circumstances changed.  (The defaults are still used for
interactive case, when datasets are transformed under user direction.)

Documentation is in `se_open_data/cli.rb`, but in brief: variables
named `SEOD_<commandname>` will set the parameters to use for the
named command.

For instance, `SEOD_DEPLOY_PARAMS` will set the CLI parameters for the `seod
deploy` command, and is useful to allow files to be deployed locally,
instead of remotely (as historically the norm). Similarly
`SEOD_TRIPLESTORE` allows overriding the default database deployment
mechanism.

For details of the CLI parameters you can set, see the documentation in
the referenced file above.

### Example .env

Setting up the environment is assumed to be performed by the caller,
and loading `.env` files is therefore out of the scope of this gem's
functionality. However, here is an example of an `.env` script which
could be sourced (with the passwords redacted), with examples of
setting an alternative config file, passwords and CLI parameters:

	PASSWORD__GEOAPIFYAPI_TXT=<redacted>
	PASSWORD__PEOPLE_JOEBLOGGS_LIME_SURVEY_PASSWORD=<redacted>
	PASSWORD__SERVICES_MAPBOX_LANDEXPLORER_TXT=<redacted>
	PASSWORD__VIRTUOSO_DBA_PASSWORD=<redacted>
	SEOD_DEPLOY_PARAMS=--owner . --group . /home/joebloggs/public_html
	SEOD_TRIPLESTORE_PARAMS=--no-via --password-id virtuoso_dba.password
	SEOD_CONFIG=production.conf


## Unit tests

The directory `test/` includes unit tests.

Run them with `rake test`

> [!TIP]
>
> You will need to installing the prerequisites first, using:
> 
>     bundle install
>
> You will then need to run `bundle exec $SHELL` to set up the
> environment, or prefix the command, like so:
>
>     bundle exec rake test


## Inline Documentation

There is quite a lot of inline documentation, which can be inspected
directly, or transformed into HTML documentation using Yard.

To do the latter:

    rake yard

This will create HTML documentation in a (.gitignored) directory
`doc/`, which can be browsed directly or published on the web.

> [!TIP]
>
> See the tip about installing prerequisites first in [Unit Tests](#Unit-Tests).

## Releasing

The normal process for releasing the code is:

- Ensure you're on the `master` branch
- Merge in any branches you need to include first (i.e. don't do the
  release on the end of a feature branch)
- Check the tests run (see ["Tests"](#`test/` - Unit tests))
  - Fix them if they don't!
- Rebase any `fixup` commits since the last release into the commits they're fixing
- Ensure nothing is left uncommitted.
- Increment the version in `se_open_data.gemspec` according to [Semantic Versioning]
  - Increment the third number if there are just small non-breaking changes
  - Increment the second otherwise (and set the third to zero)
  - Increment the first if there is a major rewrite or architectural
    change (and set the others to zero)
- Commit `se_open_data.gemspec` with the message
  *"se_open_data.gemspec - bump the version to <your version here>"*
- Tag this commit with the version, following the standard pattern 
  - i.e. prefix the version number with a `v`
- Push the commits back to the source
  - `git push`
  - `git push --tags`

Refresh and check these have gone upstream correctly.

## Folder Structure

### Top-level project files

- `Gemfile`: defines Ruby Gem dependencies
- `Rakefile`: Defines tasks, notably for running tests and generating docs
- `se_open_data.gemspec`: Gem metadata

### `bin/` - CLI scripts

See the inline documentation within these for more details.

- `env-setup`: convenience for development - run this to set your environment
- `export-lime-survey`: exports a set of responses from SEA's Lime Survey server
- `gen_converter`: a tool for generating schema converter scripts
- `schema2schema`: for converting schema files between formats
- `seod`: the CLI script
- `vocab-json`: a tool for creating `vocab.json` files, used for MykoMap v3.x

### `resources/` - content to include in the published static data

Currently this is just a CSS file.

### `test/` - Unit tests

See [Unit Tests](#Unit-Tests).

- `test_*.rb`: unit test files
- `data/`: canned data for the unit tests
- `config/`: configuration tests
- `deployment/`: deployment tests
- `stub-bin/`: contains stub executables which mock the behaviour of
  real ones
- `scripts/`: misc utilities that support testing

### `lib/se_open_data/` - Library source files

- **`config.rb`**
  - `SeOpenData::Config`: Reads, validates, and exposes configuration
    from a key-value text file, applying defaults and directory
    logic. Used across the project to set paths for resources,
    outputs, CSV schemas, and vocabulary base URIs.

- **`setup.rb`**
  - `SeOpenData::Setup`: Orchestrates the setup process: loads config,
    schema files, geocoding details, and manages the pipeline for CSV
    transformation and data serialisation. Defines an Observer class
    designed for customisation via sub-classing.

- **`cli.rb`**
  - `SeOpenData::CLI`: Implements a command-line interface for data
    operations: converting CSV formats, generating RDF, and HTML
    serialisation. Provides options for resource directory management
    and batch processing linked-data.

- **`initiative/rdf/config.rb`**
  - `SeOpenData::Initiative::RDF::Config`: Manages RDF vocabulary
    settings, CSS includes, and look-ups for standardised concepts
    (e.g., organisational structure, activities,
    qualifiers). Centralises how linked-data URIs and reference data
    are handled.

- **`initiative/rdf.rb`**: Defines serialisation logic for initiatives
  including activities, memberships, and address-related properties
  with ESSGLOBAL vocab integration.

- **`initiative/html.rb`**: Generates HTML views for initiatives,
  embedding machine-readable RDF and CSV, and offering links for both
  human and machine consumption.

- **`csv/converter/limesurveycore.rb`**: A pipeline for converting and
  normalising survey-based CSV data, with support for geolocation,
  contact normalisation, and schema transformation.

- **`vocab_to_index.rb`**: Aggregates and indexes SKOS vocabularies for
  use in linked-data and lookup scenarios. Supports language-specific
  aggregation and abbreviation conventions.


<!-- Link term index: -->
[1]: https://www.researchgate.net/publication/298313467_Contributo_metodologico_para_o_desenvolvimento_de_perfis_de_aplicacao_de_metadados_no_contexto_da_Web_Semantica
[2]: https://fileserver-az.core.ac.uk/download/pdf/154274396.pdf
[3]: https://2017.open.coop/sessions/linked-open-data-solidarity-economy/
[4]: https://www.youtube.com/watch?v=rkuGjkN6IXo&list=PL_HLd9xNlz94UDw48Ftxr64gx1yRiMHKJ&index=8
[5]: https://www.sciencedirect.com/book/monograph/9780123859655/semantic-web-for-the-working-ontologist
[6]: https://repositorio.uchile.cl/handle/2250/174651
[CSV]: https://en.wikipedia.org/wiki/Comma-separated_values
[ESSGLOBAL]: https://dev.vocabs.digitalcommons.coop/essglobal/2.1/html-content/essglobal.html
[Five Star]: https://en.wikipedia.org/wiki/Linked_data#5-star_linked_open_data
[JSON]: https://en.wikipedia.org/wiki/JSON
[LOD]: https://en.wikipedia.org/wiki/Linked_data
[Lime Survey]: https://en.wikipedia.org/wiki/LimeSurvey
[Murmurations]: https://murmurations.network/
[Open:2017]: https://2017.open.coop/
[Password Store]: https://www.passwordstore.org/
[QName]: https://en.wikipedia.org/wiki/QName
[RDF/XML]: https://en.wikipedia.org/wiki/RDF/XML
[RDF]: https://en.wikipedia.org/wiki/Resource_Description_Framework
[RIPESS]: https://www.ripess.org/
[Ruby Bundler]: https://bundler.io/
[SEA]: https://www.solidarityeconomy.coop/
[SKOS]: https://en.wikipedia.org/wiki/Simple_Knowledge_Organization_System
[SPARQL]: https://en.wikipedia.org/wiki/SPARQL
[SQL]: https://en.wikipedia.org/wiki/SQL
[SSE]: https://en.wikipedia.org/wiki/Solidarity_economy
[Semantic Versioning]: https://semver.org/
[Solidarity Economy]: https://en.wikipedia.org/wiki/Solidarity_economy
[TTL]: https://en.wikipedia.org/wiki/Turtle_(syntax)
[Virtuoso]: https://en.wikipedia.org/wiki/Virtuoso_Universal_Server
[contribution guidelines]: https://github.com/DigitalCommons#-contributing
[geocoding]: https://en.wikipedia.org/wiki/Address_geocoding
[mojibake]: https://en.wikipedia.org/wiki/Mojibake
[ssh]: https://en.wikipedia.org/wiki/Secure_Shell
[triple-store]: https://en.wikipedia.org/wiki/Triplestore

<!-- for emacs
Local Variables:
mode: markdown
eval: (flyspell-mode)
eval: (auto-fill-mode)
End:

 LocalWords:  Triplestore CLI LimeSurvey TTL geolocation queriable JSON Murmurations
 LocalWords:  APIs seod Bundler ESSGLOBAL RDF schemas Gemspec Gemfile api
 LocalWords:  executables geocodable Curado RIPESS MykoMaps URI CRM
 LocalWords:  geolocated Ontologist geocode triplestore geocoder
 LocalWords:  downloader geocontainer CSVs Downloaders ETAG env
 LocalWords:  SeOpenData localisations GeoAPIfy gitignore SEA's
 LocalWords:  bundler's bundler cronjob MykoMap URIs cronjob env
 LocalWords:  gitignored SKOS SPARQL geocoding CSV Geocoding Makefiles 
 LocalWords:  Allemang Hendler Makefile declaratively Javascript
 LocalWords:  geocoded YAML Schemas config LimeSurvey LimeSurveyCore
 LocalWords:  Rebase gemspec duplications Optionality booleans QNames
 LocalWords:  mojibake
 -->
