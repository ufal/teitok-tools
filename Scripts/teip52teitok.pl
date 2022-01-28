use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Pars# Convert the known TEITOK differences to "pure" TEI/P5

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'writeback' => \$writeback, # write back to original file or put in new file
            'output=s' => \$output, # which UDPIPE model to use
            'file=s' => \$filename, # which UDPIPE model to use
            'folder=s' => \$folder, # Originals folder
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

if ( !-e $filename ) { 
	print "No such file: $filename"; 
};

$/ = undef;
open FILE, $filename;
binmode (FILE, ":utf8");
$raw = <FILE>;
close FILE;

$raw =~ s/xmlns:/xmlnsoff_/g;
$raw =~ s/xmlns=/xmlnsoff=/g;
$raw =~ s/xml:id=/id=/g;
$raw =~ s/<tei:/</g;
$raw =~ s/<\/tei:/<\//g;

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(string => $raw);
};
if ( !$doc ) { 
	print "Invalid XML in $filename"; 
	if ( $debug ) {
		print $@;
	};
	if ( $debug > 2 ) {
		print $raw;
	};
	exit; 
};

foreach $tk ( $doc->findnodes("//text") ) {
	$tk->removeAttribute('xml:space');
};

@tokatts = ('xml:id', 'lemma', 'msd', 'pos');

# Convert w to tok
$tmp = $doc->findnodes("//text//w | //text//pc");
if ( $tmp ) { print "Converting w and pc to tok"; };
foreach $tk ( @{$tmp} ) {
	$ttype = $tk->getName();
	$tk->setName('tok');
	$tk->setAttribute('type', $ttype);
};

# Convert <surface> elements to bbox
$pcnt = 1; 
$tmp = $doc->findnodes("//facsimile//zone");
if ( $tmp ) { print "Converting zones to \@bbox"; };
foreach $zone ( @{$tmp} ) {
	$zoneid = $zone->getAttribute('id');
	$bbox = ""; $uly = $ulx = $lrx = $lry = -1;
	if ( $zone->getAttribute('uly') ) { 
		$ulx = $zone->getAttribute('ulx');
		$uly = $zone->getAttribute('uly');
		$lrx = $zone->getAttribute('lrx');
		$lry = $zone->getAttribute('lry');
	} elsif ( $zone->getAttribute('points') ) {
	}; 
	if ( $uly > -1 ) { $bbox = "$ulx $uly $lrx $lry"; };
	$corresp = $doc->findnodes("//*[\@facs=\"#$zoneid\"]") or $corresp = $doc->findnodes("//*[\@corresp=\"#$zoneid\"]");
	if ( $corresp && $bbox ) {
		$corresp->item(0)->setAttribute('bbox', $bbox);
	};
};

# Convert <choice>


# Convert sound start/end to <timeline> elements
# foreach $utt ( $doc->findnodes("//text//u") ) {
# 	$start = $utt->getAttribute('start') or $start = $utt->getAttribute('begin');
# 	$end = $utt->getAttribute('end');
# 
# 	$who = $utt->getAttribute('who');
# 	$utt->setAttribute('who', "#$who"); # Add a # since the @who is an id-ref
# 
# 	$times{$start} = 1;
# 	$times{$end} = 1;
# 
# };
# $tlnode = $doc->findnodes("//timeline")->item(0);
# if ( !$tlnode ) { 
# 	$text = $doc->findnodes("//text")->item(0); 
# 	$tlnode = $doc->createElement( 'timeline' );
# 	$tlnode->setAttribute('unit', 'ms');
# 	$text->addChild($tlnode);
# };
# @timeline = sort {$a <=> $b} keys(%times);
# $tidx = 1;
# $tlwhen = $doc->createElement( 'when' );
# $tlwhen->setAttribute('xml:id', 'T0');
# $tlnode->addChild($tlwhen);
# $last = 0; $lastidx = 'T0';
# foreach $time ( @timeline ) {
# 	$thisidx = "T".$tidx++;
# 	$tlwhen = $doc->createElement( 'when' );
# 	$tlwhen->setAttribute('since', '#'.$lastidx);
# 	$tlwhen->setAttribute('interval', ($time-$last)*1000);
# 	$tlnode->addChild($tlwhen);
# 	$last = $time; $lastidx = $thisidx;
# 	
# 	foreach $utt ( $doc->findnodes("//text//u[\@start=\"$time\"]") ) { $utt->setAttribute('start', '#'.$thisidx); };
# 	foreach $utt ( $doc->findnodes("//text//u[\@begin=\"$time\"]") ) { $utt->setAttribute('begin', '#'.$thisidx); };
# 	foreach $utt ( $doc->findnodes("//text//u[\@end=\"$time\"]") ) { $utt->setAttribute('end', '#'.$thisidx); };
# 	
# }; 

if ( $writeback ) { 
	$output = $filename;
	`mv $orgfile $orgfile.teitok`;
} elsif ( !$output ) {
	( $output = $filename ) =~ s/\.([^.]+)$/-p5\.\1/;
};
print "Writing converted file to $output\n";
open OUTFILE, ">$output";
print OUTFILE $doc->toString;	
close OUTFLE;

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
			
		} else {
			print "Failed to find or create node: $xquery";
		};
	};
};

