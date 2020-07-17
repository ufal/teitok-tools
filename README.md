# teitok-tools

Conversion tools to and from the TEITOK TEI/XML format. More scripts will be added over time.

Current script:

* `	udpipe2teitok.pl` - takes a folder with raw text files, and runs them one by one through UDPIPE to generate TEITOK/XML files 
* `manatee2teitok.pl` - takes an existing KonText project, reads the repository, and creates a settings file, plus one TEITOK/XML file for each <doc> in the corpus (doc can be customized) 
* `parseudpipe.pl` - takes any tokenized XML file and runs the list of tokens through UDPIPE 
