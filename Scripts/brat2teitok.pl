use Encode;
use utf8;
use Getopt::Long;
use XML::LibXML;

# Script to convert an EXMARaLDA text into TEITOK/XML

 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # language of input
            'plain=s' => \$plainfile, # location of the plain text file
            'morerev=s' => \$morerev, # more revision statement
            'annfolder=s' => \$annfolder, # folder to write annotation to
            'output=s' => \$outfile, # folder to write the brat file to
            );

$/ = undef; $\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };
if ( !-e $filename && $filename !~ /\.ann$/ ) { $filename .= ".ann"; };
if ( !-e $filename ) { print "No such file: $filename"; };
( $basename = $filename ) =~ s/\.[^.]+$//; $basename =~ s/.*\///;
if ( !$plainfile ) { ( $plainfile = $filename ) =~ s/\.ann$/.txt/; };
if ( !$plainfile ) { ( $plainfile = $filename ) =~ s/\.ann$/.xml/; };

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
	my $annxml = XML::LibXML->load_xml(
		string => "<spanGrp/>",
	); if ( !$annxml ) { print FILE "Not able to parse annotation"; exit; };
	$spans = $xml->findnodes("//text")->item(0);
} else {
	$spans = $xml->createElement("spanGrp");
	$root->addChild($spans);
};


$/ = "\n"; 
open FILE, "$filename";
binmode ( FILE, ":utf8" ); $cnt=1;
while (<FILE>) {
	chomp; $line = $_;
	if ( /(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) { $id = $1; $type = $2; $begin = $3; $end = $4; $th = $5; };
	if ( $line =~ /^#/ ) { next; };
	
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
	$annotation = "<span range=\"$begin-$end\" corresp=\"$span\" code=\"$type\" $auto id=\"an-".$cnt++."\"$posi>".$th."</span>\n";

	my $annnode = XML::LibXML->load_xml(
		string => $annotation,
	); if ( !$annnode ) { print FILE "Not able to parse annotation"; exit; };
	$spans->addChild($annnode->firstChild);
	$spans->appendText("\n");

};
close FILE;

open FILE, ">$outfolder/$basename.xml";
# binmode(FILE, ":utf8");
print FILE $xml->toString;
close FILE;
print "Wrote xml file to $outfolder/$basename.xml";

if ( $annfolder ) {
	open FILE, ">$annfolder/brat_$basename.xml";
	#binmode(FILE, ":utf8");
	print FILE $xml->toString;
	close FILE;
	print "Wrote annotation file to $outfolder/$basename.xml";
};


# print `perl Scripts/combinebrat.pl $basename`;
