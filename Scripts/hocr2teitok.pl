use XML::LibXML;
use Getopt::Long;
use utf8;
use POSIX qw(strftime);

# convert an hOCR file to TEI
# hOCR (https://en.wikipedia.org/wiki/HOCR) is a rich text format for OCR documents
# Maarten Janssen, 2016

$\ = "\n"; $, = "\t";
binmode(STDOUT, ":utf8");

 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # filename
            'morerev=s' => \$morerev, # add additional revisionStmt
            'output=s' => \$output, # output file
            'strippath' => \$strippath, # strip path from facs name
            );

if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = $basename.".xml"; };

$today = strftime "%Y-%m-%d", localtime;

$/ = undef;
open FILE, $filename;
binmode(FILE, ":utf8");
$raw = <FILE>;
close FILE;

$raw =~ s/ xmlns=".*?"//g;

# Check if this is valid XML to start with
$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(string => $raw, {  load_ext_dtd => 0 });
};
if ( !$doc ) { 
	print "Invalid XML in $filename";
	open OUTFILE, ">wrong.xml";
	print OUTFILE $raw;
	binmode(OUTFILE, ":utf8");
	close OUTFILE;
	exit;
};

$doc->documentElement()->setName("TEI");
$teiheader = $doc->createElement("teiHeader");

# Remove all <head> elements
foreach $elm ( $doc->findnodes("/TEI/head")->item(0) ) {
	$elm->parentNode->removeChild($elm);
};

$body = $doc->findnodes("//body")->item(0);
$body->setName("text");
$body->parentNode->insertBefore($teiheader, $body);

# Convert words
foreach $elm ( $doc->findnodes("//span[contains(\@class, 'ocrx_word')]") ) {
	$title = $elm->getAttribute('title')."";
	$bbox = ""; if ( $title =~ /bbox ([0-9.]+ [0-9.]+ [0-9.]+ [0-9.]+)/ ) { $bbox = $1; }; $bbox =~ s/\.\d+//g;
	
	$elm->setName("tok");
	foreach $att ( $elm->attributes() ) {
		$elm->removeAttribute($att->getName());
	};
	$elm->setAttribute("bbox", $bbox);
	
	while ( $elm->textContent =~ /(.*)(\p{isPunct})$/ ) {
		$form = $1; $punct = $2;
		if ( !$elm->findnodes('text()') ) { next; }; # This should not happen, but does
		$elm->findnodes('text()')->[0]->setData($form);
		$newtok = $doc->createElement("tok"); $newtok->appendText($punct);
		$elm->parentNode->insertAfter($newtok, $elm);
	};

	while ( $elm->textContent =~ /^(\p{isPunct})(.*)/ ) {
		$form = $2; $punct = $1;
		if ( !$elm->findnodes('text()') ) { next; }; # This should not happen, but does
		$elm->findnodes('text()')->[0]->setData($form);
		$newtok = $doc->createElement("tok"); $newtok->appendText($punct);
		$elm->parentNode->insertBefore($newtok, $elm);
	};

};

# Convert pages
foreach $elm ( $doc->findnodes("//div[contains(\@class, 'ocr_page')]") ) {
	$title = $elm->getAttribute('title');
	$bbox = ""; if ( $title =~ /bbox ([0-9.]+ [0-9.]+ [0-9.]+ [0-9.]+)/ ) { $bbox = $1; }; $bbox =~ s/\.\d+//g;
	$facs = ""; if ( $title =~ /image ([^ ;"]+)/ ) { $facs = $1; $facs =~ s/\"//g; };

	if ( $strippath ) {
		$facs =~ s/.*[\/\\]//;
	};

	$elm->setName("pb");
	foreach $att ( $elm->attributes() ) {
		$elm->removeAttribute($att->getName());
	};
	$elm->setAttribute("bbox", $bbox);
	$elm->setAttribute("facs", $facs);
};

# Convert lines
foreach $elm ( $doc->findnodes("//span[contains(\@class, 'ocr_line')]") ) {
	$title = $elm->getAttribute('title');
	$bbox = ""; if ( $title =~ /bbox ([0-9.]+ [0-9.]+ [0-9.]+ [0-9.]+)/ ) { $bbox = $1; }; $bbox =~ s/\.\d+//g;
	
	$elm->setName("lb");
	foreach $att ( $elm->attributes() ) {
		$elm->removeAttribute($att->getName());
	};
	$elm->setAttribute("bbox", $bbox);
};

# Convert paragraphs
foreach $elm ( $doc->findnodes("//p[contains(\@class, 'ocr_par')]") ) {
	$title = $elm->getAttribute('title');
	$bbox = ""; if ( $title =~ /bbox ([0-9.]+ [0-9.]+ [0-9.]+ [0-9.]+)/ ) { $bbox = $1; }; $bbox =~ s/\.\d+//g;
	
	foreach $att ( $elm->attributes() ) {
		$elm->removeAttribute($att->getName());
	};
	$elm->setAttribute("bbox", $bbox);
};

foreach $elm ( $doc->findnodes("//*[contains(\@title, 'bbox')]") ) {
	$elm->setName("torem");
};


# Add the revision statement
$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"hocr2teitok\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from hOCR file $basename.xml");

$teixml = $doc->toString;
$teixml =~ s/<\/lb>//g; $teixml =~ s/<lb([^>]*)>/<lb\1\/>/g;
$teixml =~ s/<\/pb>//g; $teixml =~ s/<pb([^>]*)>/<pb\1\/>/g;
$teixml =~ s/<\/torem>//g; $teixml =~ s/<torem([^>]*)>//g;

$teixml =~ s/<!DOCTYPE.*?>//g; 

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

