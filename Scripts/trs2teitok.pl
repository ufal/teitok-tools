use Getopt::Long;
use XML::LibXML;
use Data::Dumper;
use POSIX qw(strftime);

# Convert Transcriber TRS files to TEITOK/XML
# TRS is an audio transcription format from Transcriber (https://trans.sourceforge.net/en/cmd.php)
 
GetOptions ( ## Command line options
	'debug' => \$debug, # debugging mode
	'test' => \$test, # tokenize to string, do not change the database
	'file=s' => \$filename, # input file
	'output=s' => \$output, # output file
	'encoding=s' => \$encoding, # output file
	'morerev=s' => \$morerev, # language of input
	'nospace' => \$nospace, # convert to whitespace-sensitive XML
	);

$\ = "\n"; $, = "\t";


if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = $basename.".xml"; };
	
	$/ = undef;
	open FILE, $filename;
	if ( $encoding ) { binmode(FILE, ":$encoding"); };
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

$mediafile = $doc->documentElement()->getAttribute("audio_filename");
$medianode = makenode($tei, "/TEI/teiHeader/recordingStmt/recording/media");
$medianode->setAttribute("url", $mediafile);


foreach $episode ( $doc->findnodes("//Episode") ) {
	$ab = $tei->createElement("ab");
	$text->addChild($ab);
	foreach $section ( $episode->findnodes("Section") ) {
		$ug = $tei->createElement("ug");
			$start = $section->getAttribute("startTime");
			$ug->setAttribute("start", $start);
			$end = $section->getAttribute("endTime");
			$ug->setAttribute("end", $end);
		$ab->addChild($ug);
		foreach $turn ( $section->findnodes("Turn") ) {
			$u = $tei->createElement("u");
			$start = $turn->getAttribute("startTime");
			$u->setAttribute("start", $start);
			$end = $turn->getAttribute("endTime");
			$u->setAttribute("end", $end);
			$tmp = $turn->getAttribute("speaker");
			if ( $tmp ) { $u->setAttribute("who", $tmp); };
			$tmp = $turn->getAttribute("mode");
			if ( $tmp ) { $u->setAttribute("mode", $tmp); };
			$ug->addChild($u);
			foreach $node ( $turn->childNodes ) {
				if ( $node->nodeType == 1 ) {
					$time = $node->getAttribute("time");
					if ( $tok ) { $tok->setAttribute("end", $time); };
					$tok = $tei->createElement("tok");
					$u->addChild($tok);
					$tok->setAttribute("start", $time);
				} elsif ( $node->nodeType == 3 ) {
					if ( $tok ) {
						( $form = $node->textContent ) =~ s/^\s*(.*?)\s*$/\1/gsmi;
						$tok->appendText($form);
					} else {
						print "?? ".Dumper($node);
					};
				} else {
					print "?? ".Dumper($node);
				};
			};
		};
	};	
};

# Add the revision statement
$revnode = makenode($tei, "/TEI/teiHeader/revisionDesc/change[\@who=\"trs2teitok\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from TRS file $basename.trs");

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


