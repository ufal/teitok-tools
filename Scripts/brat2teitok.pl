use Encode;
use utf8;
use Getopt::Long;
use XML::LibXML;

# Script to convert an EXMARaLDA text into TEITOK/XML

 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'makesent' => \$makesent, # interpret new lines as sentence boundaries
            'file=s' => \$filename, # language of input
            'plain=s' => \$plainfile, # location of the plain text file
            'morerev=s' => \$morerev, # more revision statement
            'annfolder=s' => \$annfolder, # folder to write annotation to
            'annname=s' => \$annname, # annotation prefix
            'output=s' => \$outfile, # file to write the XML file to
            );

$/ = undef; $\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };
if ( !-e $filename && $filename !~ /\.ann$/ ) { $filename .= ".ann"; };
if ( !-e $filename ) { print "Error: annotation file not found - $filename"; };
( $basename = $filename ) =~ s/\.[^.]+$//; $basename =~ s/.*\///;
if ( !$plainfile ) { ( $plainfile = $filename ) =~ s/\.ann$/.txt/; };
if ( !$outfile ) { ( $outfile = $filename ) =~ s/\.ann$/.xml/; };

if ( !-e $plainfile ) { sleep 5; };
if ( !-e $plainfile ) { print "Error: text file not found - $plainfile"; };

$/ = undef;
# binmode(STDOUT, ":utf8");

open FILE, $plainfile;
binmode(FILE, ":utf8");
$text = <FILE>;
close FILE;

if ( $text eq "" ) { print "Text not read."; exit; }

$\ = "\n"; $, = "\t";

$ws = 0; $ss = 0; $org = 1; $toks = ""; $cnt = 1;
for $i (0..length($text)-1){
    $char = substr($text, $i, 1);
    # print "Index: $i, Text: $char \n";
    		
	$mapto{$i} = $cnt;
    if ( ( $char eq " " || $char eq "\n" ) && $org ) {
    	$we = $i; $word = substr($text, $ws, $we-$ws);
		$tokcnt = $cnt;
		
		# Split off left punctuations
		$befp = ""; 
		while ( $word =~ /^(\p{isPunct})(.+)/ ) {
			$punct = $1; $word = $2;
			$begins{$tokcnt} = $ws; $ends{$tokcnt} = $ws;
			$mapto{$ws} = $tokcnt;
			$toktxt{$tokcnt} = $punct;
    		$befp .= "<tok id=\"w-$tokcnt\" idx=\"$ws-$ws\">$punct</tok>";
			$ws++; $tokcnt++; $cnt++;
		};

		# Split off right punctuations
		$aftp = "";
		while ( $word =~ /(.+)(\p{isPunct})+/ ) {
			$punct = $2; $word = $1;
			$pcnt = $tokcnt + 1;
			$begins{$pcnt} = $we; $ends{$pcnt} = $we;
			$toktxt{$pcnt} = $punct;
			$mapto{$we} = $pcnt;
    		$aftp .= "<tok id=\"w-$pcnt\" idx=\"$we-$we\">$punct</tok>";
			$we--; $cnt++;
		};

		for ( $j=$ws; $j<$we+1; $j++ ) { $mapto{$j} = $tokcnt; };
	
    	$mf= ""; if ( $word =~ /\*/ ) { $mf = " mf=\"$word\""; $word =~ s/\*//g; };
    	$begins{$tokcnt} = $ws; $ends{$tokcnt} = $we;
    	$toktxt{$tokcnt} = $word;
    	$toks .= "$befp<tok id=\"w-$tokcnt\" idx=\"$ws-$we\"$mf>$word</tok>$aftp$char";
    	$ws = $i+1;
    	$cnt++;
    };
    if ( $makesent && $char eq "\n" ) {
    	$se = $i;
    	# print "Phrase ($org): ".substr( $text, $ss, $se-$ss );
    	if ( $org == 0 ) {
    		$ths = substr( $text, $ss, $se-$ss );
    		$toks =~ s/ $//;
    		$sent = "<s th=\"$ths\">".$toks."</s>\n";
    		$sent =~ s/ ([,.!?)])/\1/g;
    		$sent =~ s/([(]) /\1/g;
    		# print $sent;
    		$tei .= $sent;
	    	$toks = "";
    	};
    	$ss = $i+1; $ws = $i+1;
    	$org = 1-$org;
    };
           
}
if ( !$makesent ) { $tei = $toks; 	};

$tei =~ s/ (<tok[^>]+>[,.!?)])/\1/g;
$tei =~ s/([(]<\/tok>) /\1/g;

$tei = "<TEI>
<teiHeader/>
<text>
$tei</text>
$annotation</TEI>";

my $xml = XML::LibXML->load_xml(
	string => $tei,
); if ( !$xml ) { print FILE "Not able to parse generated TEI"; exit; };

$root = $xml->findnodes("//text")->item(0);

if ( $annfolder ) {
	$annxml = XML::LibXML->load_xml(
		string => "<standOff $sotype><spanGrp/><linkGrp/></standOff>",
	); if ( !$annxml ) { print FILE "Not able to parse annotation"; exit; };
	$spans = $annxml->findnodes("//spanGrp")->item(0);
	$links = $annxml->findnodes("//linkGrp")->item(0);
} else {
	$spans = $xml->createElement("spanGrp");
	$links = $xml->createElement("linkGrp");
	$stoff = $xml->createElement("standOff");
	$root->addChild($stoff);
	$stoff->addChild($spans);
	$stoff->addChild($links);
};


$/ = "\n"; 
open FILE, "$filename";
binmode ( FILE, ":utf8" ); $cnt=1;
while (<FILE>) {
	chomp; $line = $_;
	if ( $line =~ /^#/ ) { next; };

	if ( /^(R.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) {
		$bratid = $1; $type = $2; $arg1 = $3; $arg2 = $4; $th = $5; 
		if ( $arg1 =~ /(.*):(.*)/ ) { 
			$an = $1; $br1 = $2; $tmp = $br2tt{$br1} or $tmp = "[$br1]"; $id1 = "#$tmp"; 
			print "ARG1: $br1 => #$tmp";
		};
		if ( $arg2 =~ /(.*):(.*)/ ) { 
			$an = $1; $br2 = $2; $tmp = $br2tt{$br2} or $tmp = "[$br2]"; $id2 = "#$tmp"; 
		};
		$annotation = "<link source=\"$id1\" target=\"$id2\" code=\"$type\" $auto id=\"an-".$cnt++."\" brat_id=\"$bratid\" brat_def=\"$arg1-$arg2\"/>\n";
		my $annnode = XML::LibXML->load_xml(
			string => $annotation,
		); if ( !$annnode ) { print FILE "Not able to parse annotation"; exit; };
		$links->addChild($annnode->firstChild);
		$links->appendText("\n");
	} elsif ( /^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) { 
		$bratid = $1; $type = $2; $begin = $3; $end = $4; $th = $5; 
		if ( $debug ) { print "$type: $begin-$end => $th"; };

		$sep = ""; $span = ""; $spantext = "";
		for ( $i=$mapto{$begin}; $i<$mapto{$end}+1; $i++ ) {
			$span .= $sep."#w-".$i; 
			$spantext .= $sep.$toktxt{$i};
			$sep = " ";
		};
	
		# Deal with word-internal annotations
		$posi = "";
	
		if ( $th ne $spantext ) { print "Oops: $th ne $spantext"; };

		if ( $debug ) { print "  -- found at $mapto{$begin} - $mapto{$end} = $span = $spantext"; };
		$annotation = "<span corresp=\"$span\" code=\"$type\" $auto id=\"an-".$cnt++."\"$posi  brat_id=\"$bratid\" range=\"$begin-$end\">".$th."</span>\n";
		$br2tt{$bratid} = "an-".$cnt;
		my $annnode = XML::LibXML->load_xml(
			string => $annotation,
		); if ( !$annnode ) { print FILE "Not able to parse annotation"; exit; };
		$spans->addChild($annnode->firstChild);
		$spans->appendText("\n");
	};
	$br2tt{$bratid} = "an-".$cnt;
	
};
close FILE;

open FILE, ">$outfile";
# binmode(FILE, ":utf8");
print FILE $xml->toString;
close FILE;
print "Wrote xml file to $outfile";

if ( $annxml ) {
	if ( $annname eq "" ) { $annname = "brat"; };
	$annfile = "$annfolder/$annname"."_$basename.xml";
	open FILE, ">$annfile";
	#binmode(FILE, ":utf8");
	print FILE $annxml->toString;
	close FILE;
	print "Wrote annotation file to $annfile";
};


# print `perl Scripts/combinebrat.pl $basename`;
