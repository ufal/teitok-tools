use Getopt::Long;
use XML::LibXML;
use Data::Dumper;
use POSIX qw(strftime);

# Convert EAF files to TEITOK/XML
 
GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'file=s' => \$filename, # input file
            'output=s' => \$output, # output file
            'morerev=s' => \$morerev, # language of input
            'nospace' => \$nospace, # convert to whitespace-sensitive XML
            );

$\ = "\n"; $, = "\t";


if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = $basename.".xml"; };
	
	$/ = undef;
	open FILE, $filename;
	$raw = <FILE>;
	close FILE;
	
$raw =~ s/ xmlns=".*?"//g;
$raw =~ s/ version=".*?"//g;
$raw =~ s/ xmlns:xlink=".*?"//g;
$raw =~ s/ xlink:.*?=".*?"//g;
$raw =~ s/<\?.*?\?>//g;
# $raw =~ s/xml://g;
	
if ( $debug ) { print $raw; };


# Check if this is valid XML to start with
$parser = XML::LibXML->new(); $doc = "";
eval {
	$eaf = $parser->load_xml(string => $raw, { no_blanks => 1 });
};
if ( !$eaf ) { 
	print "Invalid XML in $filename";
	open FILE, ">wrong.xml";
	print FILE $raw;
	close FILE;
	print `xmllint wrong.xml`;
	exit;
};

# Create the document
$doc = $parser->load_xml(string => "<TEI></TEI>", { no_blanks => 1 });
$header = XML::LibXML::Element->new( "teiHeader" );
$doc->firstChild->appendChild($header);
$text = XML::LibXML::Element->new( "text" );
$doc->firstChild->appendChild($text);

# Read the timeline elements
foreach $node ( $eaf->findnodes("//TIME_ORDER/TIME_SLOT") ) {
	$key = $node->getAttribute("TIME_SLOT_ID")."";
	$val = $node->getAttribute("TIME_VALUE");
	if ( $debug ) { print "$key => $val"; };
	$times{$val} = $key;
	$i2t{$key} = $val;
};

# Read the tiers
foreach $tier ( $eaf->findnodes("//TIER") ) {
	$who = $tier->getAttribute("PARTICIPANT");
	$tierid = $tier->getAttribute("TIER_ID");
	$annname = $tierid; $annname =~ s/[^a-zA-Z0-9]//g;
	if ( $debug ) { print "tier: $who, $tierid"; };
	foreach $annotation ( $tier->findnodes("./ANNOTATION/ALIGNABLE_ANNOTATION") ) {
		$annid = $annotation->getAttribute("ANNOTATION_ID")."";	
		$start = $annotation->getAttribute("TIME_SLOT_REF1")."";	
		$end = $annotation->getAttribute("TIME_SLOT_REF2")."";	
		$txt = $annotation->findnodes("./ANNOTATION_VALUE")->item(0)->textContent;
		$utts{$i2t{$start}} .= "$annid;";
		$anns{$annid}{'start'} = $start;	
		$anns{$annid}{'who'} = $who;	
		$anns{$annid}{'end'} = $end;	
		$anns{$annid}{'text'} = $txt;
		print "$annid: $start-$end = $txt";
	};
	foreach $annotation ( $tier->findnodes("./ANNOTATION/REF_ANNOTATION") ) {
		$annid = $annotation->getAttribute("ANNOTATION_ID")."";	
		$annref = $annotation->getAttribute("ANNOTATION_REF")."";	
		$txt = $annotation->findnodes("./ANNOTATION_VALUE")->item(0)->textContent;
		$anns{$annref}{'refs'}{$annname} = $txt;	
		print "$annref: $annname = $txt";
	};
};

# Write the utterances
foreach my $key (sort {$a <=> $b} keys %utts) {
	$tmp = $utts{$key}; $tmp =~ s/;$//;
	foreach $annid ( split(",", $tmp) ) {
		$ann = $anns{$annid};
		$utt = XML::LibXML::Element->new( "u" );
		$utt->setAttribute("who", $ann->{'who'});
		$utt->setAttribute("start", $key/1000);
		$utt->setAttribute("end", $i2t{$ann->{'end'}}/1000);
		$utt->appendText($ann->{'text'});
		$text->appendChild($utt);
		$text->appendText("\n");
		
		while ( ( $key2, $val2) = each ( %{$ann->{'refs'}} ) ) {
			print "REF $key2 = $val2";
			$utt->setAttribute("$key2", $val2);
		};
	};
};

# Add the revision statement
$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"eaf2teitok\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from ELAN file $basename.eaf");

if ( $debug ) {
	print $doc->toString; 
	exit;
};

$teixml = $doc->toString(1);
if ( $nospace ) {
	$teixml =~ s/<\/tok>\s+/<\/tok>/gsmi;
	$teixml =~ s/\s+<tok(?=>| )/<tok/gsmi;
};

open FILE, ">$output";
print "Writing output to $output";
print FILE $teixml;
close FILE;


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

