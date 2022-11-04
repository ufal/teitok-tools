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
            'test' => \$test, # test mode - output to STDOUT
            'verbose' => \$verbose, # debugging mode
            'writeback' => \$writeback, # write back to original file or put in new file
            'output=s' => \$output, # which UDPIPE model to use
            'file=s' => \$filename, # which UDPIPE model to use
            'folder=s' => \$folder, # Originals folder
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = $basename."-p5.xml"; };

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename);
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };

foreach $tk ( $doc->findnodes("//text") ) {
	$tk->removeAttribute('xml:space');
};

@tokatts = ('xml:id', 'lemma', 'msd', 'pos', 'join');
@handled = ('ord', 'head', 'ohead', 'deprel');

# Convert <dtok> to <tok> (to be dealt with later)
foreach $tk ( $doc->findnodes("//text//tok[dtok]") ) {
	$tk->setName('w');
	foreach $dtk ( $tk->findnodes("text()") ) {
		$text = $dtk->textContent;
		$tk->removeChild($dtk);
	};
	foreach $att ( $tk->attributes() ) {
		$tk->removeAttribute($att->getName());
	};
	foreach $dtk ( $tk->findnodes("dtok") ) {
		$dtk->setName('tok');
		$form = $dtk->getAttribute('form');
		$txt = $doc->createTextNode( $form );
		$form = $dtk->removeAttribute('form');
		$dtk->addChild($txt);
	};
	if ( $tk->getAttribute('nform')) {
	print $tk->toString; exit;
	};
};


# Convert bbox  to <surface> elements
$pcnt = 1; 
foreach $bboxelm ( $doc->findnodes("//text//*[\@bbox]") ) {
	$bbox = $bboxelm->getAttribute('bbox');
	if ( $bboxelm->getName() eq 'pb' ) {
		$page = $bboxelm;
	} else {
		$page = $bboxelm->findnodes("./preceding::pb")->item(0);
	};
	$pbid = $page->getAttribute('id');
	$spag = $spags{$pbid};
	if ( !$spag ) {
		$spag = $doc->createElement( 'surface' );
		if ( $page->getAttribute('n') ) {
			$spag->setAttribute('n', $page->getAttribute('n'));
		};
		$graph = $doc->createElement( 'graphic' );
		$graph->setAttribute('url', $page->getAttribute('facs'));
		$spag->addChild($graph);
		$facs = makenode($doc, "/TEI/facsimile");
		$facs->addChild($spag);
		$spid = 'PF'.$pcnt++; $zcnt{$spid} = 1;
		$spag->setAttribute('xml:id', $spid);
		$spags{$pbid} = $spag;
	} else { $spid = $spag->getAttribute('xml:id'); };
	( $x1, $y1, $x2, $y2 ) = split ( " ", $bboxelm->getAttribute('bbox') );
	$zone = $doc->createElement( 'zone' );
	$zone->setAttribute('ulx', $x1);
	$zone->setAttribute('uly', $y1);
	$zone->setAttribute('lrx', $x1);
	$zone->setAttribute('lry', $y2);
	$zid = $spid.'-Z'.$zcnt{$spid}++;
	$zone->setAttribute('xml:id', $zid);
	$spag->addChild($zone);
	$bboxelm->setAttribute('corresp', '#'.$zid);
	
	# Remove the bbox
	$bboxelm->removeAttribute('bbox');
};

# Remove the @id from pb, lb
foreach $node ( $doc->findnodes("//*[\@id]") ) {
	$val = $node->getAttribute('id');
	$node->removeAttribute('id');
	$node->setAttribute('xml:id', $val);
};

# Remove all <ee/>
foreach $node ( $doc->findnodes("//ee") ) {
	$node->parentNode->removeChild($node);
};

# Convert <tok> to <w> and <pc>
$tcnt = 0;
foreach $tk ( $doc->findnodes("//text//tok") ) {

	$tkid =  $tk->getAttribute('id') or $tkid =  $tk->getAttribute('xml:id') ;

	# Add @join
	undef($tkp); $tmp = $tk; $join = 0;
	if ( !$tk->nextSibling() ) { while ( $tmp->parentNode() &&  $tmp->parentNode()->getName() ne 's' ) { $tkp = $tmp->parentNode(); $tmp = $tkp; }; };
	if ( $tk->nextSibling() && $tk->nextSibling()->getName() eq "tok" ) { 
		$join = 1; 
	} elsif ( $tkp && $tkp->nextSibling() && $tkp->nextSibling()->getName() eq "tok" ) { $join = 1; };
	if ( $join ) { $tk->setAttribute("join", "right"); };

	$wpc = "w";
	if ( $tk->getAttribute('upos') ) {
		if ( $tk->getAttribute('upos') eq 'PUNCT' ) { $wpc = "pc"; };
	} else {
		$word = $tk->textContent;
		if ( $word =~ /^\p{isPunct}+$/ ) { $wpc = "pc"; };
	};
	$tk->setName($wpc);

	
	if ( $tk->getAttribute('upos') ) {
		# Convert CoNNL-U to msd
		$msd = 'UposTag='.$tk->getAttribute('upos');
		if ( $tk->getAttribute('feats') ne '_' & $tk->getAttribute('feats') ne '' ) { $msd .= '|'.$tk->getAttribute('feats'); };
		$tk->setAttribute('msd', $msd);
		$tk->removeAttribute('upos');
		$tk->removeAttribute('feats');
		$tk->removeAttribute('xpos');

	};
	
	if ( $tk->getAttribute('head') ) {
		# Convert dependency relations to <linkGrp> elements

		$lnkgrp = $tk->findnodes("./ancestor::s/linkGrp")->item(0);
		if ( !$lnkgrp) { 
			$sent = $tk->findnodes("./ancestor::s")->item(0);
			if ( !$sent ) { $sent = $tk->findnodes("//text")->item(0); }; 
			$lnkgrp = $doc->createElement( 'linkGrp' );
			$lnkgrp->setAttribute('type', 'UD-SYN');
			$sent->addChild($lnkgrp);
		};
		$link = $doc->createElement( 'link' );
		$link->setAttribute('ana', 'ud-syn:'.$tk->getAttribute('deprel'));
		$link->setAttribute('target', '#'.$tkid.' '.'#'.$tk->getAttribute('head'));
		$lnkgrp->addChild($link);
		
	};

	# Rename id to xml:id
	if ( $tk->getAttribute('id') ) {
		$tk->setAttribute('xml:id', $tk->getAttribute('id'));
		$tk->removeAttribute('id');
	};
	
	if ( $tk->getAttribute('nform') || $tk->getAttribute('reg') ) {
		$choice = $doc->createElement( 'choice' );
		$tk->parentNode->insertAfter($choice, $tk);
		$orig = $doc->createElement( 'orig' );
		$choice->addChild($orig);
		$orig->addChild($tk);
		$reg = $doc->createElement( 'reg' );
		$choice->addChild($reg);
		$regw = $doc->createElement( $wpc );
		$reg->addChild($regw);
		$nform = $tk->getAttribute('nform') or $nform = $tk->getAttribute('reg') ;
		$txt = $doc->createTextNode( $nform );
		$regw->addChild($txt);
	};
	
	if ( $tk->getAttribute('fform') || $tk->getAttribute('expan') ) {
		$choice = $doc->createElement( 'choice' );
		$tk->parentNode->insertAfter($choice, $tk);
		$orig = $doc->createElement( 'abbr' );
		$choice->addChild($orig);
		$orig->addChild($tk);
		$reg = $doc->createElement( 'expan' );
		$choice->addChild($reg);
		$regw = $doc->createElement( $wpc );
		$reg->addChild($regw);
		$fform = $tk->getAttribute('fform') or $fform = $tk->getAttribute('expan') ;
		$txt = $doc->createTextNode( $fform );
		$regw->addChild($txt);
	};

	# Remove all attributes that are not P5
	foreach $att ( $tk->attributes() ) {
		$attname = $att->getName();
		if ( !grep /^$attname$/, @tokatts ) {
			if ( $debug && !grep /^$attname$/, @handled ) { 
				print "Removing invalid attribute for $tkid: $attname = ".$att->value;
			};
			$tk->removeAttribute($attname);
		};
	};

	if ( $debug ) {
 			print $tk->toString;
 	};
		
};


# Convert sound start/end to <timeline> elements
foreach $utt ( $doc->findnodes("//text//u") ) {
	$start = $utt->getAttribute('start') or $start = $utt->getAttribute('begin');
	$end = $utt->getAttribute('end');

	$who = $utt->getAttribute('who');
	$utt->setAttribute('who', "#$who"); # Add a # since the @who is an id-ref

	$times{$start} = 1;
	$times{$end} = 1;
	$timed = 1;
};
if ( $timed ) {
$tlnode = $doc->findnodes("//timeline")->item(0);
if ( !$tlnode ) { 
	$text = $doc->findnodes("//text")->item(0); 
	$tlnode = $doc->createElement( 'timeline' );
	$tlnode->setAttribute('unit', 'ms');
	$text->addChild($tlnode);
};
@timeline = sort {$a <=> $b} keys(%times);
$tidx = 1;
$tlwhen = $doc->createElement( 'when' );
$tlwhen->setAttribute('xml:id', 'T0');
$tlnode->addChild($tlwhen);
$last = 0; $lastidx = 'T0';
foreach $time ( @timeline ) {
	$thisidx = "T".$tidx++;
	$tlwhen = $doc->createElement( 'when' );
	$tlwhen->setAttribute('since', '#'.$lastidx);
	$tlwhen->setAttribute('interval', ($time-$last)*1000);
	$tlnode->addChild($tlwhen);
	$last = $time; $lastidx = $thisidx;
	
	foreach $utt ( $doc->findnodes("//text//u[\@start=\"$time\"]") ) { $utt->setAttribute('start', '#'.$thisidx); };
	foreach $utt ( $doc->findnodes("//text//u[\@begin=\"$time\"]") ) { $utt->setAttribute('begin', '#'.$thisidx); };
	foreach $utt ( $doc->findnodes("//text//u[\@end=\"$time\"]") ) { $utt->setAttribute('end', '#'.$thisidx); };
	
};};

# Add the revision statement
$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"teitok2p5\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("Converted from TEITOK file $basename.xml");

# Deal with the namespace
$doc->findnodes("/TEI")->item(0)->setAttribute('xmlns', 'http://www.tei-c.org/ns/1.0');
$doc->findnodes("/TEI")->item(0)->removeAttribute('xmlnsoff');

if ( $test ) {
	print  $doc->toString(1);	
	exit;
};

if ( $writeback ) { 
	$output = $filename;
	`mv $orgfile $orgfile.teitok`;
} elsif ( !$output ) {
	( $output = $filename ) =~ s/\.([^.]+)$/-p5\.\1/;
};
$outputxml = $doc->toString;
($tmp = $outputxml ) =~ s/tei\_//g;
eval {
	$tmp2 = $parser->load_xml(string => $tmp);
};
if ( $tmp2 ) { $doc = $tmp2; } elsif ($debug && $tmp ne $outputxml) { print "could not convert tei_"; };
if ( $verbose ) { print "Writing converted file to $output\n"; };
open OUTFILE, ">$output";
print OUTFILE $doc->toString(1);	 # TODO - indentation does not work since parser did not (and cannot) use no_blanks
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

