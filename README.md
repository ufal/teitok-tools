# teitok-tools

Conversion tools to, from, and related to the tokenized TEI/XML format. 
These scripts can be used independently from the [TEITOK](http://www.teitok.org) platform, even though they
were build primarily with TEITOK in mind. 
More scripts will be added over time.

Current scripts:

* `	udpipe2teitok.pl` - create TEITOK/XML files parsed with UDPIPE out of raw text files
* `manatee2teitok.pl` - create a TEITOK project out of an existing KonText corpus 
* `xmltokenize.pl` - tokenize an XML file
* `parseudpipe.pl` - parse a tokenized XML file and parse it with UDPIPE

## udpipe2teitok

Takes a folder with raw text files, and runs them one by one through UDPIPE to generate TEITOK/XML files. The UDPIPE output is 
stored in a folder `udpipe`, and the resulting TEITOK/XML files in a folder `xmlfiles`. The names of the the parse and output
files mimick the names and file structure of the original files. The output files contain a `<s>` for
each sentence and a `<tok>` for each token, where the tokens contains the parse attributes 
lemma, upos, xpos, feats, head, deprel, and deps as attributes. 
Heads refer to the unique `@id` rather than to the ordinal number in the sentence like they do in UD.

Example usage:
`
perl udpipe2teitok.pl --orgfolder=Originals --lang=cs
`

Command line options:
* model - the UDPIPE model to be used (which has to be available in the REST API)
* lang - an indication of the language (either an ISO code or a name) in case no model is provided
* orgfolder - the folder where the raw text files are located.

## manatee2teitok

Takes an existing KonText project, reads the repository, and creates a settings file and the TEITOK/XML files

Example usage:

`
perl manatee2teitok.pl --corpus=legaltext_cs_a
`

Command line options:
* force - write even if project exists
* corpus - corpus to be converted
* regfolder - registry folder (if not /opt/kontext/data/registry)
* corpfolder - the name of the folder where to create the TEITOK project 
* textnode - Node to use in the input to split XML files (default: <doc>)

## xmltokenize

Takes any XML file and tokenizes its text body (`<text>` for TEI, `<body>` for HTML, other filetypes have to be
specified). Tokenization is done by adding a token node around each token (by default `<tok>`),
where a token is any text surrounded by spaces, with punctuation marks (any character in the Unicode PUNCT block) at the
beginning and the end of the words split off as a separate token. If the tokenization breaks existing tags, those tags will
be split - so `some<i>thing strange<i>` will be tokenized into  `<tok>some<i>thing</i></tok><i> <tok>strange</tok><i>`. 
In rare cases, this process leads to invalid XML and the incorrect XML will not be written back to the file, but rather to
/tmp/wrong.xml. TEI files can furthermore be optionally segmented into sentences, where a new sentence is supposed 
after any token !, ?, or .

Example usage:

`
perl xmltokenize.pl --file=test.xml --enumerate --tok=w
`

Command line options:
* filename=s - filename of the file to tokenize
* textnode=s - what to use as the text body to tokenize
* tok=s - what to use as a token node
* exlude=s - elements not to tokenize
* enumerate - provide a unique ID to each token
* segment=i - split into sentences (1=yes, 2=only) - only for TEI files

## parseudpipe

Takes any tokenized XML file and runs the list of tokens through UDPIPE. If the XML file is not segmented into 
sentences, it will assume the start of a new sentence after each !,?,. The resulting parse data
lemma, upos, xpos, feats, head, deprel, and deps are added to the token nodes as attributes. In case sentences
and tokens do not have an `@id` attribute they will be assigned a sequential identifier, which is used in the parsing
process - and heads refer to the unique `@id` rather than to the ordinal number in the sentence like they do in UD.

Example usage:

`
perl parseudpipe.pl --file=test.xml --atts=reg,full --sent=s --tok=tok --lang=English
`

Command line options:
* writeback - write back to original file or put in new file
* file - which UDPIPE model to use
* model - which UDPIPE model to use
* lang - language of the texts (if no model is provided)
* folder - Originals folder
* token - token node
* tokxp - token XPath
* sent - sentence node
* sentxp - sentence XPath
* atts - attributes to use for the word form
