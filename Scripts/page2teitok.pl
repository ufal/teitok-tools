use XML::LibXML;
use Getopt::Long;
use utf8;
use Data::Dumper;
use POSIX qw(strftime);

# convert a Page XML to TEITOK/XML
# PageXML is a rich format for HTR document, for instance from Transkribus
# Maarten Janssen, 2021

$\ = "\n"; $, = "\t";
binmode(STDOUT, ":utf8");

 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # test mode (do not save)
            'file=s' => \$filename, # filename
            'morerev=s' => \$morerev, # add additional revisionStmt
            'output=s' => \$output, # output file
            'strippath' => \$strippath, # strip path from facs name
            'nopunct' => \$nopunct, # do not split off punctuation marks
            'nofolders' => \$nofolders, # do not split off punctuation marks
            'noretoken' => \$noretoken, # do not merge across linebreaks
            );

if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = "xmlfiles/$basename.xml"; };

$today = strftime "%Y-%m-%d", localtime;

if ( !-e $filename) {
	print "No such file: $filename";
	exit;
}

$/ = undef;
open FILE, $filename;
binmode(FILE, ":utf8");
$raw = <FILE>;
close FILE;

$raw =~ s/ xmlns=".*?"//g;

# Check if this is valid XML to start with
$parser = XML::LibXML->new(); $doc = "";
eval {
	$input = $parser->load_xml(string => $raw, {  load_ext_dtd => 0 });
};
if ( !$input ) { 
	print "Invalid XML in $filename";
	open OUTFILE, ">wrong.xml";
	print OUTFILE $raw;
	binmode(OUTFILE, ":utf8");
	close OUTFILE;
	exit;
};

if ( !$input->findnodes("/PcGts") ) {
	print "Not a PageXML file! $filename";
	exit;
};

$fnr = 0; $enr = 0; 
foreach $page ( $input->findnodes("/PcGts/Page") ) {
	$fnr++; $facsid= "facs-".$fnr;
	$enr++; $pageid= "e-".$enr;
	$imageurl = $page->getAttribute('imageFilename');
	if ( !$nofolders ) { $imageurl = "$basename/$imageurl"; };
	$facstext .= "  <surface id=\"$facsid\">";
	$text .= "\n<pb id=\"$pageid\" corresp=\"#$facsid\" facs=\"$imageurl\"/>";
	$anr = 0; 
	foreach $area ( $page->findnodes("./TextRegion") ) {
		$points = ""; $bbox = "";
		$tmp = $area->findnodes("./Coords");
		if ( $tmp ) { 
			$points = $tmp->item(0)->getAttribute('points'); 
			$bbox = makebb($points);
		};	
		$anr++; $facsid2 = "facs-$fnr.a$anr";
		$enr++; $divid= "e-".$enr;
		$facstext .= "\n\t<zone id=\"$facsid2\" rendition=\"TextRegion\" points=\"$points\"/>";
		$text .= "\n<div id=\"$divid\" corresp=\"#$facsid2\" bbox=\"$bbox\">";
		foreach $line ( $area->findnodes("./TextLine") ) {
			$points = ""; $bbox = ""; $plnr = 0;
			$tmp = $line->findnodes("./Coords");
			if ( $tmp ) { 
				$points = $tmp->item(0)->getAttribute('points'); 
				$bbox = makebb($points);
			};	
			$lnr++; $facsid3 = "facs-$fnr.l$lnr";
			$lbid= "lb-$fnr.$lnr";
			$facstext .= "\n\t<zone id=\"$facsid3\" rendition=\"Line\" points=\"$points\"/>";
			$text .= "\n<lb id=\"$lbid\" corresp=\"#$facsid3\" bbox=\"$bbox\"/>";
			$tmp = $line->findnodes("./TextEquiv/Unicode");
			$linetext = ""; if ( $tmp ) { $linetext = $tmp->item(0)->textContent; };
			$linetext =~ s/^\s+|\s+$//gsmi;
			if ( $line->findnodes("./Word") ) {
				$tokenized = 1; $wnr = 0;
				foreach $word ( $line->findnodes("./Word") ) {
					$points = ""; $bbox = ""; $plnr = 0;
					$tmp = $word->findnodes("./Coords");
					if ( $tmp ) { 
						$points = $tmp->item(0)->getAttribute('points'); 
						$bbox = makebb($points);
					};	
					$wnr++; $facsid4 = "facs-$fnr.l$lnr.w$wnr";
					$tokid= "w-$fnr.$lnr.$wnr";
					$tmp = $word->findnodes("./TextEquiv/Unicode");
					$toktext = ""; if ( $tmp ) { $toktext = $tmp->item(0)->textContent; };
					$toktext =~ s/^\s+|\s+$//gsmi;
					$aftpunc = ""; $befpunc = "";
					if ( !$nopunct && $toktext !~ /^[A-Z](\p{P})$/ ) {
						# Move on-boundary punctuation marks out of the token
						while ( $toktext =~ /(.*)(\p{P})$/ ) {
							$wnr++; $ptokid= "w-$fnr.$lnr.$wnr";
							$toktext = $1; $aftpunc .= "<tok id=\"$ptokid\">$2</tok>";
						};
						while ( $toktext =~ /^(\p{P})(.*)/ ) {
							$wnr++; $ptokid= "w-$fnr.$lnr.$wnr";
							$toktext = $2; $befpunc .= "<tok id=\"$ptokid\">$1</tok>";
						};
					};
					$facstext .= "\n\t<zone id=\"$facsid4\" rendition=\"Word\" points=\"$points\"/>";
					$text .= "\n  $befpunc<tok id=\"$tokid\" corresp=\"#$facsid4\" bbox=\"$bbox\">$toktext</tok>$aftpunc";
				};
			} else {
				# Deal with the @custom field: reading order and tags
				$custom = $line->getAttribute('custom');
				undef(%begin); undef(%end);
				if ( $custom ) {
					while ( $custom =~ s/^([^ ]+) \{([^{}]+)\} *// ) {
						$key = $1; $val = $2;
						if ( $val =~ /offset:(\d+); length:(\d+);(.*)/ ) {
							$lbl = $key; $lbl2 = "";
							if ( $lbl eq 'textStyle' ) { $lbl = "hi"; $lbl2 = "_".$3; $lbl2 =~ s/:.*//; };
							$off = $1; $len = $2;
							$begin{$off-1} .= "$lbl$lbl2;";
							$end{$off+$len} .= "$lbl;";
						};
					};
					$annline = "";
					$linetext =~ s/^\s+|\s+$//g;
					for ( $i=0; $i<length($linetext)+2; $i++ ) {
						if ( $end{$i} ) {
							foreach $lbl ( split(";", $end{$i} ) ) {
								if ( $lbl ) { $annline .= "</$lbl>"; };
							}; 
						};
						if ( $begin{$i} ) {
							foreach $lbl ( split(";", $begin{$i} ) ) {
								if ( $lbl ) { $annline .= "<$lbl>"; };
							}; 
						};
						$annline .= substr($linetext, $i,1);
					};
					$annline =~ s/<hi_([^<>]+)>/<hi rend="\1">/g;;
					# Check this stayed valid XML
					undef($ctest);
					eval { $ctest = $parser->load_xml(string => "<line>$annline</line>", {  load_ext_dtd => 0 }); };
					if ( $ctest ) { $linetext = $annline; } 
					elsif ( $debug ) { 
						print "Oops: $annline";
						print $line->getAttribute('custom');
						print "---------- "; 
					};
				};
				$text .= " ".$linetext;
			};
		};
		$text .= "\n</div>";
	};
	$facstext .= "\n  </surface>";
};

if ( !$noretoken ) {
	# change <tok>trun-</tok> <lb/> <tok>cation</tok> to <tok>trun-<lb/>cation</tok>
	$text =~ s/<tok([^<>]*)>([^<>]+)<\/tok><tok[^<>]*>-<\/tok>\s*(<lb[^<>]*\/>)\s*<tok([^<>]*)>([^<>]+)<\/tok>/<tok form="\2\5"><gtok\1>\2-<\/gtok>\3<gtok\4>\5<\/gtok><\/tok>/gxmi;
};

$when = strftime "%Y-%m-%d", localtime;
$teixml = "<TEI>
<teiHeader>
	<revisionDesc>
		<change when=\"$when\" who=\"pages2teitok\">Converted from PageXML file $basename.xml</change>
	</revisionDesc>
</teiHeader>
<facsimile>
$facstext
</facsimile>
<text>$text
</text>
</TEI>";

$check = $parser->load_xml(string => $teixml, {  load_ext_dtd => 0 });
if ( !$check ) { print "Oops - turned into invalid XML"; exit; };

if ( $test ) {
	print "Conversion completed"; 
	print $check->toString;
	exit;
};

open FILE, ">$output";
print "Writing output to $output";
print FILE $check->toString;
close FILE;

sub makebb ( $tmp ) {
	$tmp = @_[0]; if ( $tmp eq '' ) { return ""; };
	$x2 = $y2 = 0; $x1 = $y1 = 1000000000000;
	foreach $tmp2 ( split(" ", $tmp) ) {
		($x,$y) = split(',', $tmp2);
		if ( $x > $x2 ) { $x2 = $x; };
		if ( $x < $x1 ) { $x1 = $x; };
		if ( $y > $y2 ) { $y2 = $y; };
		if ( $y < $y1 ) { $y1 = $y; };
	};
	$bb = "$x1 $y1 $x2 $y2";
	return $bb;
};

sub makenode ( $xml, $xquery ) {
	my ( $xml, $xquery ) = @_;
	@tmp = $xml->findnodes($xquery); 
	if ( scalar @tmp ) { 
		$node = shift(@tmp);
		if ( $debug ) { print "Node exists: $xquery"; };
		return $node;
	} else {
		if ( $xquery =~ /^(.*)\/(.*?)$/ ) {
			my $parxp = $1; my $thisname = $2;
			my $parnode = makenode($xml, $parxp);
			$thisatts = "";
			if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
				$thisname = $1; $thisatts = $2;
			};
			if ( $thisname =~ /^@(.*)/ ) {
				$attname = $1;
				$parnode->setAttribute($attname, '');
				foreach $att ( $parnode->attributes() ) {
					if ( $att->getName eq $attname ) {
						return $att;
					};
				};
			} else {
				$newchild = XML::LibXML::Element->new( $thisname );
			
				# Set any attributes defined for this node
				if ( $thisatts ne '' ) {
					if ( $debug ) { print "setting attributes $thisatts"; };
					foreach $ap ( split ( " and ", $thisatts ) ) {
						if ( $ap =~ /\@([^ ]+) *= *"(.*?)"/ ) {
							$an = $1; $av = $2; 
							$newchild->setAttribute($an, $av);
						};
					};
				};

				if ( $debug ) { print "Creating node: $xquery ($thisname)"; };
				$parnode->addChild($newchild);
			};
			
		} else {
			print "Failed to find or create node: $xquery";
		};
	};
};

