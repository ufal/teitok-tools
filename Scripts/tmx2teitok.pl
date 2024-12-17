use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Convert a TXM file to TEITOK/XML
# TMX (https://help.transifex.com/en/articles/6838724-tmx-files-and-format) is a format for translation memories

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # which UDPIPE model to use
            'output=s' => \$output, # which UDPIPE model to use
            'morerev=s' => \$morerev, # language of input
            'split' => \$split, # Split into 1 file per language
            );

$\ = "\n"; $, = "\t";
if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename);
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };

$tunr = 1;
foreach $tu ( $doc->findnodes("//tu") ) {
	$appid = $basename.":tu-".$tunr++;
	
	foreach $tuv ( $tu->findnodes(".//tuv") ) {
		$lang = $tuv->getAttribute('lang');
		$segtxt = $tuv->findnodes(".//seg")->item(0)->textContent;
		$langparts{$lang} .= "\n<ab appid=\"$appid\">$segtxt</ab>";
	};
	
};

if ( $split ) {
	while ( ( $key, $val) = each ( %langparts) ) {
		( $output = $filename ) =~ s/\.tmx/-$key.xml/;
		print "Writing converted file to $output\n";
		open OUTFILE, ">$output";
		binmode(OUTFILE, ":utf8");
		print OUTFILE "<TEI>\n<teiHeader>
<revisionDesc>
	$morerev<change who=\"tmx2teitok\" when=\"$today\">Converted from TMX file $filename</change>
</teiHeader>\n<text lang=\"$key\">$val</text>\n</TEI>";
		close OUTFLE;
	};
} else {
	if ( !$output ) { ( $output = $filename ) =~ s/\.tmx/.xml/; };
	print "Writing converted file to $output\n";
	open OUTFILE, ">$output";
	binmode(OUTFILE, ":utf8");
	print OUTFILE "<TEI>\n<teiHeader>
<revisionDesc>
	$morerev<change who=\"tmx2teitok\" when=\"$today\">Converted from TMX file $filename</change>
</revisionDesc>
</teiHeader>\n<text>";
	
	while ( ( $key, $val) = each ( %langparts) ) {
		print OUTFILE "\n<div lang=\"$key\">$val</div>\n";
	};
		
	print OUTFILE "</text>\n</TEI>";
	close OUTFLE;

};