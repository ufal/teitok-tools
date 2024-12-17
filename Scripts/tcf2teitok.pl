use Getopt::Long;
use XML::LibXML;
use Data::Dumper;
use POSIX qw(strftime);

# Convert TCF files to TEITOK/XML
# TCF (https://github.com/weblicht/tcf-spec) is an interchange format used by WebLicht
 
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
	$doc = $parser->load_xml(string => $raw, { no_blanks => 1 });
};
if ( !$doc ) { 
	print "Invalid XML in $filename";
	open FILE, ">wrong.xml";
	print FILE $raw;
	close FILE;
	print `xmllint wrong.xml`;
	exit;
};

$tei = 	$parser->load_xml(string => "<TEI/>", { no_blanks => 1 });
$teiheader = $tei->createElement("teiHeader");
$tei->firstChild->addChild($teiheader);
$text = $tei->createElement("text");
$tei->firstChild->addChild($text);

@tokarray = ();
foreach $tok ( $doc->findnodes("//token") ) {
	$forms{$tok->getAttribute("ID").""} = $tok->textContent;
	push(@tokarray, $tok->getAttribute("ID")."");
};

foreach $node ( $doc->findnodes("//lemmas/lemma") ) {
	if (!$forms{$node->getAttribute("tokenIDs").""}) { print "Which token? ".$node->getAttribute("tokenIDs").""; };
	$atts{$node->getAttribute("tokenIDs").""}{"lemma"} = $node->textContent;
};
foreach $node ( $doc->findnodes("//POStags/tag") ) {
	if (!$forms{$node->getAttribute("tokenIDs").""}) { print "Which token? ".$node->getAttribute("tokenIDs").""; };
	$atts{$node->getAttribute("tokenIDs").""}{"pos"} = $node->textContent;
};
foreach $node ( $doc->findnodes("//orthography/correction") ) {
	if (!$forms{$node->getAttribute("tokenIDs").""}) { print "Which token? ".$node->getAttribute("tokenIDs").""; };
	$atts{$node->getAttribute("tokenIDs").""}{"reg"} = $node->textContent;
};
foreach $node ( $doc->findnodes("//depparsing//dependency") ) {
	if (!$forms{$node->getAttribute("depIDs").""}) { print "Which token? ".$node->getAttribute("tokenIDs").""; };
	if( $node->getAttribute("govIDs") && $node->getAttribute("depIDs") ) { $atts{$node->getAttribute("depIDs").""}{"head"} = $node->getAttribute("govIDs"); };
	if( $node->getAttribute("func") && $node->getAttribute("depIDs") ) { $atts{$node->getAttribute("depIDs").""}{"deprel"} = $node->getAttribute("func"); };
};


if ( $doc->findnodes("//sentences") ) {
	$totsent = scalar @{$doc->findnodes("//sentence")};
	foreach $sent ( $doc->findnodes("//sentence") ) {
		$teis = $tei->createElement("s");
		$text->addChild($teis);
		$teis->setAttribute("id", $sent->getAttribute("ID"));
		foreach $tokid ( split(" ", $sent->getAttribute("tokenIDs"))) {
			$teitok = $tei->createElement("tok");
			$teitok->appendText($forms{$tokid});
			$teitok->setAttribute("id", $tokid);
			$tokhash{$tokid} = $teitok;
			$tosent{$tokid} = $sent->getAttribute("ID");
			$teis->addChild($teitok);
			
			while ( ( $key, $val ) = each ( %{$atts{$tokid}} ) ) {
				$teitok->setAttribute($key, $val);
			};
		};
	};
} else {
	foreach $tokid ( @tokarray ) {
		$teitok = $tei->createElement("tok");
		$teitok->setAttribute("id", $tokid);
		$teitok->appendText($forms{$tokid});
		$tokhash{$tokid} = $teitok;
		$text->addChild($teitok);
	};
};

# Named Entities
foreach $node ( $doc->findnodes("//namedEntities//entity") ) {
	@toklist = split(" ", $node->getAttribute("tokenIDs"));
	$first = $tokhash{$toklist[0]};
	$mtok = $tei->createElement("name");
	$first->parentNode->insertBefore( $mtok, $first);
	
	if ( $node->getAttribute("class") ) { $mtok->setAttribute("type", $node->getAttribute("class").""); };
	if ( $node->getAttribute("ID") ) { $mtok->setAttribute("id", $node->getAttribute("ID").""); };
	
	foreach $tokid ( @toklist ) {
		$mtok->addChild($tokhash{$tokid})
	};
};

# Parse trees
if ( $doc->findnodes("//parsing") ) {
	$forest = $tei->createElement("forest");
	$text->addChild($forest);
	foreach $tree ( $doc->findnodes("//parsing//parse") ) {
		$tmp = $doc->findnodes(".//constituent[\@tokenIDs]")->item(0)->getAttribute("tokenIDs");
		@tmp2 =  split(" ", $tmp);
		$firsttok = $tmp2[0];
		$tree->setAttribute("sentid", $tosent{$firsttok});
		$tree->setName("eTree");
		foreach $node ( $tree->findnodes(".//constituent") ) {
			$node->setName("eTree");
			if ( $node->getAttribute("cat") ) {
				$node->setAttribute("Label", $node->getAttribute("cat")."");
				$node->removeAttribute("cat");
			};
			$node->setAttribute("id", $node->getAttribute("ID")."");
			$node->removeAttribute("ID");
			if ( $node->getAttribute("tokenIDs") ) {
				$tokid =  $node->getAttribute("tokenIDs")."";
				$node->setAttribute("tokid", $tokid);
				$node->removeAttribute("tokenIDs");
				$leaf = $tei->createElement("eLeaf");
				$node->addChild($leaf);
				$leaf->setAttribute("Text", $forms{$tokid});
			};
		};
		$forest->addChild($tree);
	};
};

# Add the revision statement
$revnode = makenode($tei, "/TEI/teiHeader/revisionDesc/change[\@who=\"tcf2teitok\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from TCF file $basename.xml");

if ( $debug ) {
	print $tei->toString; 
	exit;
};

$teixml = $tei->toString(1);
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


