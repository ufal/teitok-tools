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
            'file=s' => \$filename, # filename to convert
            'output=s' => \$output, # filename for the converted file
            'morerev=s' => \$morerev, # additional revision nodes to put in the header
            'mode=s' => \$mode, # mode : join (one TEI xml file with different DIVs), split (one TEI file per language), annotate (TEI per language with @trans attribute)
            'tuvelm=s' => \$tuvelm, # element to use for each tu (default: ab)
            'tuid=s' => \$tuid, # element to use for the @tuid (default: tuid)
            );

$\ = "\n"; $, = "\t";
if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;

if ( !$tuvelm ) { $tuvelm = "ab"; };
if ( !$tuid ) { $tuid = "tuid"; };

$today = strftime "%Y-%m-%d", localtime;

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename);
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };

$tunr = 1;
foreach $tu ( $doc->findnodes("//tu") ) {
	$appid = $basename.":tu-".$tunr++;
	
	foreach $tuv ( $tu->findnodes(".//tuv") ) {
		$lang = $tuv->getAttribute('xml:lang') or $lang = $tuv->getAttribute('lang');
		$segtxt = $tuv->findnodes(".//seg")->item(0)->textContent;
		if ( $mode eq 'annotate' ) {
			$tseg{$lang} = $segtxt;
			$ttr{$lang} = 1;
		} else {
			$langparts{$lang} .= "\n<$tuvelm $tuid=\"$appid\">$segtxt</$tuvelm>";
		};
	};
	
	if ( $mode eq 'annotate' ) {
		while ( ($key, $val) = each ( %tseg ) ) { 
			$trans = "";
			$segtxt = $val;
			while ( ($key2, $val2) = each ( %ttr ) ) { 
				$val2 = $tseg{$key2};
				if ( $val2 && $key ne $key2 ) { 
					$val2 =~ s/\&/\&amp;/g; $val2 =~ s/"/\&#037;/g; $val2 =~ s/</\&lt;/g; $val2 =~ s/>/\&gt;/g;
					$trans .= " trans_$key2=\"$val2\"";
				};
			};
			$langparts{$key} .= "\n<$tuvelm $tuid=\"$appid\"$trans>$segtxt</$tuvelm>";
		};
	};
	
};

if ( $mode eq 'split' || $mode eq 'annotate' ) {
	$outbase = $output or $outbase = $filename;
	while ( ( $key, $val) = each ( %langparts) ) {
		( $output = $outbase ) =~ s/\.(tmx|xml)/-$key.xml/;
		print "Writing converted file for $key to $output\n";
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