use Getopt::Long;
use XML::LibXML;

# Convert a TEI/XML document into plain text

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'mixed' => \$mixed, # mixed language corpus - detect for each text
            'file=s' => \$filename, # which UDPIPE model to use
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

$/ = undef;
open FILE, $filename;
binmode(FILE, ":utf8");
$xml = <FILE>;
close FILE;

$xml =~ s/.*<text[^>]*>//sm;
$xml =~ s/<\/text>.*//sm;

$xml =~ s/\n+/ /g;
$xml =~ s/<del(?=>| ).*?<\/del>//g;
$xml =~ s/<p>/\n\n/g;
$xml =~ s/<[^>]+>//g;
$xml =~ s/ +/ /g;

print $xml;