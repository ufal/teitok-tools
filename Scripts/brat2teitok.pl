use Encode;
use utf8;
use Getopt::Long;
use XML::LibXML;

# Script to convert an BRAT annotated file (txt + ann) into TEITOK/XML
# Brat (https://brat.nlplab.org/) is a tool to create stand-off annotations

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # debugging mode
            'keeppunct' => \$keeppunct, # keep punctuation marks inside the token
            'makesent' => \$makesent, # interpret new lines as sentence boundaries
            'makepar' => \$makepar, # interpret double new lines as paragraph boundaries
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
( $basename = $filename ) =~ s/\.[^.]+$//; $basename =~ s/.*\///; $basename =~ s/\.xml$//;
if ( !$plainfile ) { ( $plainfile = $filename ) =~ s/\.ann$/.txt/; };
if ( !$outfile ) { ( $outfile = $filename ) =~ s/\.ann$/.xml/; };

if ( !-e $plainfile ) { sleep 5; }; # Wait for conversion if input is not plain text (not used for BRAT)
if ( !-e $plainfile ) { print "Error: text file not found - $plainfile"; };

$/ = undef;
binmode(STDOUT, ":utf8");

open FILE, $plainfile;
binmode(FILE, ":utf8");
$text = <FILE>;
close FILE;

if ( $text eq "" ) { print "Text not read."; exit; }

$\ = "\n"; $, = "\t";

$ws = 0; $ss = 0; $toks = ""; $cnt = 1; # $org = 1; 
if ( $makepar ) { $toks .= "<p>"; };
if ( $makesent ) { $toks .= "<s>"; $newsent = 1; };
for $i (0..length($text)-1){
    $char = substr($text, $i, 1);
    # print "Index: $i, Text: $char \n";
    		
	$mapto{$i} = $cnt;
	if ( ( $char eq " " || $char eq "\n" ) ) { # && $org 
    	# Assume a new token on each space or linebreak
    	$we = $i; $word = substr($text, $ws, $we-$ws);
		$tokcnt = $cnt; 
		
		if ( !$keeppunct ) {
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
		};

		for ( $j=$ws; $j<$we+1; $j++ ) { $mapto{$j} = $tokcnt; };
	
    	$mf= ""; if ( $word =~ /\*/ ) { $mf = " mf=\"$word\""; $word =~ s/\*//g; };
    	$begins{$tokcnt} = $ws; $ends{$tokcnt} = $we;
    	$word =~ s/&(?![^ ]+;)/&amp;/g;
    	$word =~ s/</&lt;/g;
    	$word =~ s/>/&gt;/g;
    	$toks .= $befp;
    	if ( $we > $ws ) {
	    	$toktxt{$tokcnt} = $word;
    		$toks .= "<tok id=\"w-$tokcnt\" idx=\"$ws-$we\"$mf>$word</tok>";
	    	$cnt++;
	    };
    	$toks .= $aftp.$char;
	    $ws = $i+1;
    } else {
    	$newsent = 0;
    };
    if ( $makesent && $char eq "\n" ) {
    	# Create a new sent on newline if in sent mode
    	$se = $i;
    	$sent = substr($text, $ss, $se-$ss);
    	if ( $debug ) { print "Sentence: $sent"; };
    	if ( $sent eq "\n"  && $makepar ) {
    		# Empty line
	    	$toks .= "</s></p><p><s>"; 
    	} elsif ( $ss == $se && $makepar ) {
    		# Empty line
	    	$toks .= "</s></p><p><s>"; 
    	} else {
	    	$toks .= "</s><s>"; 
	    };
     	$ss = $i+1;
    };
    $par =0;
           
}
if ( $makesent ) { $toks .= "</s>"; };
if ( $makepar ) { $toks .= "</p>"; };
$toks =~ s/([\n\r]+)<\/tok>/<\/tok>\1/g;
$toks =~ s/<tok[^<>]*><\/tok>//g;
$tei = $toks;

$tei =~ s/ (<tok[^>]+>[,.!?)])/\1/g;
$tei =~ s/([(]<\/tok>) /\1/g;

# Remove empty sentences
$tei =~ s/<s>(\n*)<\/s>/\1/g;
$tei =~ s/<p>(\n*)<\/p>/\1/g;

# Move linebreaks outside <s> and <p>
$tei =~ s/\n<\/s>/<\/s>\n/g;
$tei =~ s/\n<\/p>/<\/p>\n/g;
$tei =~ s/\n<\/s>/<\/s>\n/g;
$tei =~ s/\n<\/p>/<\/p>\n/g;

$tei = "<TEI>
<teiHeader/>
<text>
$tei</text>
$annotation</TEI>";

eval { $xml = XML::LibXML->load_xml( string => $tei, ); 
}; if ( !$xml ) { 
	print "Not able to parse generated TEI"; 
	if ( $verbose ) { print $@; };
	if ( $debug ) { print $tei; };
	exit; 
};

$root = $xml->findnodes("//text")->item(0);

if ( $annfolder ) {
	$annxml = XML::LibXML->load_xml(
		string => "<standOff $sotype><spanGrp/><linkGrp/></standOff>",
	); if ( !$annxml ) { print "Not able to parse annotation"; exit; };
	$spans = $annxml->findnodes("//spanGrp")->item(0);
	$links = $annxml->findnodes("//linkGrp")->item(0);
} else {
	$spans = $xml->createElement("spanGrp");
	$links = $xml->createElement("linkGrp");
	$stoff = $xml->createElement("standOff");
	$root->addChild($stoff);
	$stoff->addChild($spans);
	$stoff->appendText("\n");
	$stoff->addChild($links);
};


$/ = "\n"; 
open FILE, "$filename";
binmode ( FILE, ":utf8" ); $cnt=1;
while (<FILE>) {
	chomp; $line = $_;
	if ( $line =~ /^#/ ) { next; };

	if ( $line =~ /^(R\d+)\t(.*)/ ) {
		# Relation
		$bratid = $1; $rest = $2;
		print "Relation: $bratid => $rest";
		( $type, $arg1, $arg2 ) = split(" ", $rest); 
		if ( $arg1 =~ /(.*):(.*)/ ) { 
			$an = $1; $br1 = $2; $tmp = $br2tt{$br1} or $tmp = "[$br1]"; $id1 = "#$tmp"; 
			print "- ARG1: $br1 => #$tmp";
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
	} elsif ( $line =~ /^(E\d+)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) {
		# Event
	} elsif ( $line =~ /^(\*)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) {
		# Equivalence
	} elsif ( $line =~ /^(A\d+)\t(.*)/ ) {
		# Annotation over T layers
		$bratid = $1; $rest = $2;
		( $ann, $type ) = split(" ", $rest); 
		$lnk = $br2tt{$ann};
		$th = $br2txt{$ann};
		print "Annotation: $bratid => $ann, $arg";
		
		$annotation = "<span corresp=\"#$lnk\" code=\"$type\" id=\"an-".$cnt++."\"  brat_id=\"$bratid\">".$th."</span>\n";
		$br2tt{$bratid} = "an-".$cnt;
		my $annnode = XML::LibXML->load_xml(
			string => $annotation,
		); if ( !$annnode ) { print FILE "Not able to parse annotation"; exit; };
		$spans->addChild($annnode->firstChild);
		$spans->appendText("\n");
	} elsif ( $line =~ /^(T\d+)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/ ) { 
		# Text-bound annotation
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
		$br2txt{$bratid} = $th;
	
		$th =~ s/[\n\r]/ /g; $th =~ s/ +/ /g; $th =~ s/^ +| +$//g;
		$spantext =~ s/[\n\r]/ /g; $spantext =~ s/ +/ /g; $spantext =~ s/^ +| +$//g;
		if ( $th ne $spantext ) { print "Oops: \n{$th}\n=/=\n{$spantext}"; };

		if ( $debug ) { print "  -- found at $mapto{$begin} - $mapto{$end} = $span = $spantext"; };
		$annotation = "<span corresp=\"$span\" code=\"$type\" $auto id=\"an-".$cnt++."\"$posi  brat_id=\"$bratid\" range=\"$begin-$end\">".$th."</span>\n";
		$br2tt{$bratid} = "an-".$cnt;
		my $annnode = XML::LibXML->load_xml(
			string => $annotation,
		); if ( !$annnode ) { print FILE "Not able to parse annotation"; exit; };
		$spans->addChild($annnode->firstChild);
		$spans->appendText("\n");
	} else {
		print "Unknown type of Annotation: \n$line"; exit;
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
