use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Convert TEITOK documents to the WebLicht TCF format
# TCF (https://github.com/weblicht/tcf-spec) is an interchange format used by WebLicht

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # vebose mode
            'help' => \$help, # help
            'longid' => \$longid, # write tok_id= in the misc column
            'norepair' => \$norepair, # do not repair tree errors
            'file=s' => \$filename, # input file name
            'posatt=s' => \$posatt, # name to use for pos
            'pos=s' => \$posatt, # XPOS tag
            'lang=s' => \$cqplang, # XPOS tag
            'form=s' => \$wform, # form to use as word
            'output=s' => \$output, # output file name
            'outfolder=s' => \$outfolder, # Originals folder
            'tagmapping=s' => \$tagmapping, # XPOS tag
            'training' => \$training, # write back to original file or put in new file
            );

$\ = "\n"; $, = "\t";

$parser = XML::LibXML->new(); 

if ( !$filename ) { $filename = shift; };
if ( $debug ) { $verbose = 1; };

if ( $help ) {
	print "Usage: perl teitok2conllu.pl [options] filename

Options:
	--verbose	verbose output
	--debug		debugging mode
	--file		filename to convert
	--output	conllu file to write to
	--pos=s		XML attribute to use for @xpos
	--form=s	TEITOK inherited form to use as @form
	";
	exit;

};

if ( !$posatt ) { $posatt = "pos"; };
if ( !$wform ) { 
	$wform = "pform"; 
} else {
	# We need an inheritance from the settings
	$doc = "";
	$setfile = "Resources/settings.xml"; 
	if ( $verbose ) { print "Reading settings from $setfile for inheritance from $wform	"; };
	eval {
		$setxml = $parser->load_xml(location => $setfile);
	};
	if ( $setxml ) { foreach $node ( $setxml->findnodes("//xmlfile/pattributes/forms/item") ) {
		$from = $node->getAttribute("key");
		$to = $node->getAttribute("inherit");
		$inherit{$from} = $to;
	};};
	if ( !$inherit{'form'} ) { $inherit{'form'} = "pform"; };
};
if ( $debug ) { while ( ( $key, $val ) = each ( %inherit ) ) { print "Inherit: $key => $val"; }; };

if ( $tagmapping && -e $tagmapping ) {
	open FILE, $tagmapping;
	binmode(FILE, ":utf8");
	while ( <FILE> ) {
		chop;
		( $xpos, $upos, $feats ) = split ( "\t" );
		$xpos2upos{$xpos} = $upos;
		$xpos2feats{$xpos} = $feats;
	};
	close FILE;
};

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename);
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };

if ( !$cqplang ) { if ( $tmp = $doc->findnodes("//language/\@ident") ) { $cqplang = $tmp->item(0)->value; }; };
if ( !$cqplang ) { $cqplang = "en"; };

$tmp = "<D-Spin xmlns=\"http://www.dspin.de/data\" version=\"5\">
  <md:MetaData xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:cmd=\"http://www.clarin.eu/cmd/\" xmlns:md=\"http://www.dspin.de/data/metadata\" xsi:schemaLocation=\"http://www.clarin.eu/cmd/ http://catalog.clarin.eu/ds/ComponentRegistry/rest/registry/profiles/clarin.eu:cr1:p_1320657629623/xsd\">
  </md:MetaData>
</D-Spin>";
$tcf = $parser->load_xml(string => $tmp, no_blanks => 1);
$tcft = $tcf->createElement("TextCorpus"); $tcf->firstChild->addChild($tcft);
	$tcft->setAttribute("xmlns", "http://www.dspin.de/data/textcorpus");
	$tcft->setAttribute("lang", $cqplang);
$sec{'text'} = $tcf->createElement("tc:text"); $tcft->addChild($sec{'text'});
	$sec{'text'}->setAttribute("xmlns:tc", "http://www.dspin.de/data/textcorpus");
$sec{'tokens'} = $tcf->createElement("tc:tokens"); $tcft->addChild($sec{'tokens'});
	$sec{'tokens'}->setAttribute("xmlns:tc", "http://www.dspin.de/data/textcorpus");
$sec{'sentences'} = $tcf->createElement("tc:sentences"); $tcft->addChild($sec{'sentences'});
	$sec{'sentences'}->setAttribute("xmlns:tc", "http://www.dspin.de/data/textcorpus");

if ( !$output && $outfolder ) { 
	( $output = $filename ) =~ s/\.xml/.conllu/; 
	if ( $outfolder ) { 
		$output =~ s/.*\//$outfolder\//;
	};
} else {
	( $ofldr = $output ) =~ s/[^\/]+$//;
	if ( $debug ) { print "Creating $ofldr when needed"; };
	if ( $oflder ) { `mkdir -p $ofldr`; };
};

if ( !$doc->findnodes("//tok") ) {
	print "Error: cannot convert untokenized files to CoNNL-U";
	exit;
};

# Convert <dtok> to <tok> (to be dealt with later)
$scnt = 1;

$docid = $filename; $docid =~ s/.*\///; $docid =~ s/\.xml//;

# print OUTFILE "# newdoc id = $docid";
$sents = $doc->findnodes("//s");
if ( !scalar $sents ) { $sents = $doc->findnodes("//u"); };
if ( $sents ) { 
	if ( $verbose ) { print "With sentences"; };
	$sntcnt = 0;
	foreach $snt ( @{$sents} ) {
		$sentid = $snt->getAttribute('id');
		if ( !$sentid ) { 
			$sentid = "[$sntcnt]"; 
			if ( $verbose ) { print "Unnumbered sentence $sentid"; };
		}; 
		if ( $debug ) { print $sntcnt, $sentid };
		$sntcnt++;
		@toks =  $snt->findnodes(".//tok[not(dtok)] | .//dtok");
		if ( ! scalar @toks ) { 
			if ( $verbose ) { print "Skipping empty sentence $sentid"; };
			next; 
		};
		$senttxt = $snt->textContent;
		$senttxt =~ s/\s/ /g; $senttxt =~ s/ +/ /g; $senttxt =~ s/^ | $//g;
		
		$outsent = $tcf->createElement("tc:sentence"); $sec{'sentences'}->addChild($outsent);
		undef(%toknrs); # Undef to avoid sentence-crossing links

		if ( !$norepair ) {
			# Check for loops
			$headed = 0;
			$tree = $parser->load_xml(string => "<s/>");
			undef(%nodes); undef(%id2tok); undef($rootid); undef($unrootid); undef($root);
			foreach $tok ( @toks ) {
				$tokid =  $tok->getAttribute("id");
				$id2tok{$tokid} = $tok;
				$nodes{$tokid} = $tree->createElement("tok");
				if ( $tok->getAttribute("head") ) {
					$headed = 1;
				};
				if ( $tok->getAttribute("deprel")."" eq "root" ) {
					if  ( !$rootid ) { $rootid = $tokid; };
				} elsif ( !$tok->getAttribute("head") || $tok->getAttribute("head")."" eq ""  ) {
					$unrootid = $tokid;
				}; 
			}; 
			if ( $headed && !$rootid && $unrootid ) { 
				if ( $verbose ) { print "No explicit root - using unheaded $unrootid"; };
				if ( $id2tok{$unrootid} ) {
					$id2tok{$unrootid}->setAttribute("deprel", "root");
				};
				$rootid = $unrootid; 
			};
			if ( $headed && !$rootid ) { 
				$tmp = $toks[0]; 
				while  ( $tmph = $tmp->getAttribute("head") && $id2tok{$tmph} ) {
					$tmp = $id2tok{$tmph};
				};
				$rootid = $tmp->getAttribute("id");
				if ( $verbose ) { print "No root element found in $sentid - setting to $rootid"; };
			} elsif ( $debug  ) { print "Root ID: $rootid"; };
				
			if ( $headed ) {
			foreach $tok ( @toks ) {
				$tokid =  $tok->getAttribute("id")."";
				$headid =  $tok->getAttribute("head")."";
				$deprel =  $tok->getAttribute("deprel")."";
				if ( $rootid && $tokid ne $rootid && $deprel eq "root" ) {
					if  ( $verbose ) { print "Linked or secondary marked as root in $sentid/$tokid (renaming to dep)"; };
					$tok->setAttribute("deprel", "dep"); # We should not keep multiple roots
				};
				if ( $headid && $tokid ne $rootid ) { 
					if ( !$nodes{$headid} ) { 
						if ( $verbose ) { print "Reference to non-existing node in $sentid: $tokid -> $headid (reattaching to $rootid)"; };
						$tok->setAttribute("head", $rootid);
						$nodes{$rootid}->addChild($nodes{$tokid});
					} elsif ( $nodes{$headid}->findnodes(".//ancestor::tok[\@id=\"$tokid\"]") ) { 
						if ( $verbose ) { print "Circular dependency in $sentid: $tokid -> $headid (reattaching to $rootid)"; };
						$tok->setAttribute("head", $rootid);
						$nodes{$rootid}->addChild($nodes{$tokid});
					} else { eval {
						$nodes{$headid}->addChild($nodes{$tokid});
					}; };
					if ( !$nodes{$tokid}->parentNode ) { 
						if ( $verbose ) { print "Failed to attach $tokid in $sentid to $headid (reattaching to $rootid)"; };
						$tok->setAttribute("head", $rootid);
						$nodes{$rootid}->addChild($nodes{$tokid});
					};
				} else {
					if ( $tokid ne $rootid ) { 
						if  ( $verbose ) { print "Multiple roots in $sentid: $rootid and $tokid (reattaching to $rootid)"; };
						$tok->setAttribute("head", $rootid);
						$tok->setAttribute("deprel", "dep"); # We should not keep multiple roots
					};
					$tree->firstChild->addChild($nodes{$tokid});
				};
			}; };
		};
		foreach $tok ( @toks ) {
			$sentlines .= parsetok($tok);
		};
		$sentids =~ s/ $//;
		$outsent->setAttribute("tokenIDs", $sentids); $sentids = "";
		$toknr = 0;
	};
} else {
	if ( $verbose ) { print "Without sentences"; };
	$snum = 1;
	foreach $tok ( $doc->findnodes("//tok") ) {
		if ( $newsent ) { 
# 			print OUTFILE "# text = $senttxt";
			$sentlines = ""; $senttxt = "";
			$toknr = 0;
		};
		$newsent = 0;
		$tokxml = parsetok($tok); $sentlines .= $tokxml; 
		@tmp = split("\t", $tokxml); 
		$senttxt .= $tmp[1]; if ( $tmp[9] !~ /Space/ ) { $senttxt .= " "; };
		if ( $tmp[1] =~ /^[.!?]$/ ) { 
			$newsent = 1;
		};
		$num++;
	};
	if ( $sentlines ) {
		$sentlines = ""; $senttxt = "";
		$toknr = 0;
	};
};

$sec{'text'}->appendText($fulltext);

open OUTFILE, ">$output";
print OUTFILE $tcf->toString(1);	 # TODO - indentation does not work since parser did not (and cannot) use no_blanks
close OUTFLE;

sub parsetok($tk) {
	$tk = @_[0];
	if ( !$tk ) { return -1 };
	
	$toknr++; 
	$toklinenr = $toknr;
	$tokid = $tk->getAttribute('id').'';
	$toknrs{$tokid} = $toknr;
	$word = calcform($tk, $wform);
	$word =~ s/\s+$//gsm;
	$word =~ s/&#039;/''/g;
	$lemma = getAttVal($tk, 'lemma');
	$upos = getAttVal($tk, 'upos');
	$xpos = getAttVal($tk, $posatt);
	$feats = getAttVal($tk, 'feats');
	$head = getAttVal($tk, 'head');
	$deprel = getAttVal($tk, 'deprel');
	$deps = getAttVal($tk, 'deps');
	$misc = getAttVal($tk, 'misc');

	$outtok = $tcf->createElement("tc:token"); $sec{'tokens'}->addChild($outtok);
	$outtok->setAttribute("ID", $tokid);
	$outtok->appendText($word);
	
	$sentids .= "$tokid ";
	
	$fulltext .= $word;

	if ( $upos ne "" && $upos ne "_" ) {
		if ( !$sec{'upos'} ) {
			$sec{'upos'} = $tcf->createElement("tc:POStags"); $tcft->addChild($sec{'upos'});
			$sec{'upos'}->setAttribute("tagset", "universal-pos");
			$sec{'upos'}->setAttribute("xmlns:tc", "http://www.dspin.de/data/textcorpus");
		}; 
		$tmp = $tcf->createElement("tc:tag"); $sec{'upos'}->addChild($tmp);
		$tmp->setAttribute("ID", $tokid."-upos");
		$tmp->setAttribute("tokenIDs", $tokid);
		$tmp->appendText($upos);
	};

	if ( $lemma ne "" && $lemma ne "_" ) {
		if ( !$sec{'lemmas'} ) {
			$sec{'lemmas'} = $tcf->createElement("tc:lemmas"); $tcft->addChild($sec{'lemmas'});
			$sec{'lemmas'}->setAttribute("xmlns:tc", "http://www.dspin.de/data/textcorpus");
		}; 
		$tmp = $tcf->createElement("tc:lemma"); $sec{'lemmas'}->addChild($tmp);
		$tmp->setAttribute("ID", $tokid."-lemma");
		$tmp->setAttribute("tokenIDs", $tokid);
		$tmp->appendText($lemma);
	};


	if ( $deprel eq '_' && $training ) { $deprel = "dep"; }; # We always need a deprel for training the parser

	if ( $misc eq '_' ) { $misc = ""; };
	if ( $misc ) { $misc = $misc."|"; };
	if ( $longid ) { 
		$misc .= $tokid; 
	} else {
		$misc .= "tokId=".$tokid; 
	};
	
	# fallback
	if ( $word eq '' ) { $word = "_"; };
	if ( $misc eq '' ) { $misc = "_"; };
	
	undef($tkp); $tmp = $tk;
	if ( !$tk->nextSibling() ) { while ( $tmp->parentNode() &&  $tmp->parentNode()->getName() ne 's' ) { $tkp = $tmp->parentNode(); $tmp = $tkp; }; };
	if ( $tk->nextSibling() && $tk->nextSibling()->getName() eq "tok" ) { $misc .= "|SpaceAfter=No"; 
	} elsif ( $tkp && $tkp->nextSibling() && $tkp->nextSibling()->getName() eq "tok" ) { $misc .= "|SpaceAfter=No"; };
		
	if ( $misc!~ /SpaceAfter=No/ )	{ 	$fulltext .= " "; };
		
	return; 
	
};

sub getAttVal ($node, $att ) {
	( $node, $att ) = @_;
	$val = $node->getAttribute($att);
	$val =~ s/^\s+|\s+$//g;
	$val =~ s/\t| //g;
	$val =~ s/ +/ /g;
	
	if ( !$val ) { $val = "_"; };
	
	return $val;
};

sub calcform ( $node, $form ) {
	( $node, $form ) = @_;
	if ( !$node ) { return; };
	
	if ( $form eq 'pform' ) {
		$value = $node->toString;
		$value =~ s/<[^>]*>//g;
		return $value;
		# return $node->textContent;
	} elsif ( $node->getAttribute($form) ) {
		return $node->getAttribute($form);
	} elsif ( $inherit{$form} ) {
		return calcform($node, $inherit{$form});
	} else {
		return "_";
	};
};