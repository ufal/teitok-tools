# teitok-tools

Conversion tools to and from the TEITOK TEI/XML format. More scripts will be added over time.

Current scripts:

* `	udpipe2teitok.pl` - create TEITOK/XML files parsed with UDPIPE out of raw text files
* `manatee2teitok.pl` - create a TEITOK project out of an existing KonText corpus 
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
