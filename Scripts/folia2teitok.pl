use Getopt::Long;
use XML::LibXML;
use Data::Dumper;
use POSIX qw(strftime);

# Convert FoLIA files to TEITOK/XML
# Folia (https://proycon.github.io/folia/) is a linguistic annotation format
 
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

$doc->findnodes("/FoLiA")->item(0)->setName('TEI');
# Add the header
$teiheader = $doc->createElement("teiHeader");
$doc->firstChild->insertBefore($teiheader, $doc->firstChild->firstChild);

if ( $debug ) { print "Dealing with metadata"; };
$metas{'title'} = "/TEI/teiHeader/fileDesc/titleStmt/title";
$metas{'language'} = "/TEI/teiHeader/profileDesc/langUsage/language/\@ident";
$metas{'genre'} = "/TEI/teiHeader/profileDesc/textClass/keywords/term[\@type=\"genre\"]";
$metas{'originalsource'} = "/TEI/teiHeader/notesStmt/note[\@n=\"orgfile\"]";
while ( ( $key, $xp ) = each (%metas) ) {
	$metanode = $doc->findnodes("//meta[\@id=\"$key\"]");
	if ( $metanode ) { 
		$metaval = $metanode->item(0)->textContent;
		$headernode = makenode($doc, $xp);
		if ( $headernode->nodeType() == 2 ) {
			$headernode->parentNode->setAttribute($headernode->getName, $metaval);
		} else {
			$headernode->appendText($metaval);
		};
	};
};

if ( $debug ) { print "Dealing with text"; };
foreach $textnode ( $doc->findnodes("//text") ) {
	$lang = $textnode->findnodes("./lang")->item(0);
	if ( $lang ) { 	
		$langt = $lang->getAttribute('class');
		$textnode->setAttribute('lang', $langt); 
		$textnode->removeChild($lang);
	};
	if ( $nospace ) { $textnode->setAttribute('xml:space', 'preserve'); };
};

if ( $debug ) { print "Dealing with sentences"; };
foreach $sent ( $doc->findnodes("//s") ) {
	$sentid = $sent->getAttribute('pdtid');
	foreach $text ( $sent->findnodes("./t") ) { 
		$textatt = $text->getAttribute('class') or $textatt = "text";	
		$sent->setAttribute($textatt, $text->textContent); 
		$sent->removeChild($text);
	};
};

if ( $debug ) { print "Dealing with corrections"; };
foreach $corr ( $doc->findnodes("//correction[.//original]") ) {
	$tmp = scalar(@{$corr->findnodes(".//original/w")});
	if ( $tmp == 1 ) {
		# A single original
		$tomove = $corr->findnodes(".//original/w")->item(0);
		$tomove->setName("tok");
		$txt = $tomove->findnodes("./t")->item(0)->textContent;
		$tomove->appendText($txt);
		foreach $newtok ( $corr->findnodes(".//new/w") ) {
			$tomove->addChild($newtok);
			$newtok->setName("dtok");
			$txt = $newtok->findnodes("./t")->item(0);
			$newtok->setAttribute("nform", $txt->textContent);
			$newtok->removeChild($txt)
		};
	} elsif ( $tmp == 0 ) {
		# No original
		$token = $corr->findnodes("ancestor::w")->item(0);
		if ( $token ) {
			$sep = ""; $reg = "";
			foreach $wrd ( $corr->findnodes(".//new//t") ) {
				$reg .= $sep.$wrd->textContent;
				$sep = " ";
			};
			$token->setAttribute("nform", $reg);
			foreach $wrd ( $corr->findnodes(".//original//t") ) {
				$token->insertBefore($wrd, $token->firstChild);
			};
		} else {
			# print "Non-word correction without a word: ".$corr->toString;
		};
	} else {
		$sep = ""; $reg = "";
		$tomove = $corr->findnodes(".//original")->item(0);
		$tomove->setName("mtok");
		foreach $newtok ( $corr->findnodes(".//new/w/t") ) {
			$reg .= $sep.$newtok->textContent;
			$corrid = $newtok->parentNode->getAttribute("xml:id");
			$sep = " ";
		};
		$tomove->setAttribute('nform', $reg);
		$tomove->setAttribute('xml:id', $corrid);
	};	
	if ( $tomove ) {
		$corr->parentNode->insertBefore($tomove, $corr);
		if ( $tmp == 1 && $tomove->getAttribute('space') ne 'no' ) { 
			 $c = $doc->createElement("c");
			 $c->appendText(' ');
			 $tomove->parentNode->insertAfter($c, $tomove);
			 $tomove->removeAttribute('space');
		};
	};
};
foreach $corr ( $doc->findnodes("//correction[.//current]") ) {
	foreach $curr ( $corr->findnodes(".//current/w") ) {
		$corr->parentNode->insertBefore($curr, $corr);
	};
};


if ( $debug ) { print "Dealing with tokens"; };
foreach $tok ( $doc->findnodes("//w") ) {
	$tok->setName('tok'); $toktext = "";
	foreach $attnode ( $tok->childNodes ) {
		$attname = $attnode->getName();
		if ( $attname eq '#text' ) { 
			# Ignore text nodes below <w>
			# print $attnode->toString;
		} elsif ( $attname eq 't' ) { 
			$toktext = $attnode->textContent;
		} else {
			$attval = $attnode->getAttribute('class') or $attval = $attnode->firstChild->textContent;
			$attval =~ s/\s+//;
			if ( $attval ne '' ) {
				$tok->setAttribute($attname, $attval);
			} else {
				# print "No value: ".$attnode->toString;
			};
		};
		$tok->removeChild($attnode);
	};
	$tok->appendText($toktext);
	if ( $tok->getAttribute('space') ne 'no' ) { 
		 $c = $doc->createElement("c");
		 $c->appendText(' ');
		 $tok->parentNode->insertAfter($c, $tok);
		 $tok->removeAttribute('space');
	};
};

if ( $debug ) { print "Dealing with dependencies"; };
foreach $dep ( $doc->findnodes("//dependency") ) {
	$deprel = $dep->getAttribute('class');
	$tokid = $dep->findnodes(".//dep/wref")->item(0)->getAttribute('id');
	$head = $dep->findnodes(".//hd/wref")->item(0)->getAttribute('id');
	$tok = $doc->findnodes("//tok[\@xml:id=\"$tokid\"]")->item(0);
	if ( $tok ) { 
		$tok->setAttribute('head', $head);
		$tok->setAttribute('deprel', $deprel);
	} else {
		print "Token not found: $tokid <= ".$dep->toString;
	};
};
# Now, remove the dependencies
$deps = $doc->findnodes("//dependencies")->item(0);
if ( $deps ) { $deps->parentNode->removeChild($deps); };

# Deal with Syntax (how??)
foreach $remnode ( $doc->findnodes("//syntax") ) {
	$remnode->parentNode->removeChild($remnode); 
};

# Deal with Morphology (how??)
foreach $remnode ( $doc->findnodes("//morphology") ) {
	$remnode->parentNode->removeChild($remnode); 
};

# Now, remove the nodes we cannot deal with
@noknows = (
	"entities", # MWE?
	"phonology", # Phonolgy
	"chunking", # Non-MWE chunks
	"timing", # time-alignment, but not in a usable fashion
	"semroles", # semantic role annotation
	"statements", # ??
	"metric", # element counts
	"metadata", # metadata - all about the annotation
	"foreign-data", # non-FoLiA data
	"correction", # any remaining corrections
	"t", # any remaining text nodes
);
foreach $noknow ( @noknows ) { 
	foreach $remnode ( $doc->findnodes("//$noknow") ) {
		$remnode->parentNode->removeChild($remnode); 
	};
};

# Add the revision statement
$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"folia2teitok\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from FoLiA file $basename.xml");

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

