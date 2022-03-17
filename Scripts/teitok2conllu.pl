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
            'verbose' => \$verbose, # debugging mode
            'writeback' => \$writeback, # write back to original file or put in new file
            'file=s' => \$filename, # input file name
            'posatt=s' => \$posatt, # name to use for pos
            'form=s' => \$wform, # form to use as word
            'output=s' => \$output, # output file name
            'folder=s' => \$folder, # Originals folder
            'pos=s' => \$posatt, # XPOS tag
            'tagmapping=s' => \$tagmapping, # XPOS tag
            'training' => \$training, # write back to original file or put in new file
            );

$\ = "\n"; $, = "\t";
if ( !$filename ) { $filename = shift; };

if ( !$posatt ) { $posatt = "pos"; };
if ( !$form ) { $form = "pform"; };

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

if ( !$output ) { ( $output = $filename ) =~ s/\.xml/.conllu/; };

if ( !$doc->findnodes("//tok") ) {
	print "Error: cannot convert untokenized files to CoNNL-U";
	exit;
};

print "Writing converted file to $output\n";
open OUTFILE, ">$output";
binmode(OUTFILE, ":utf8");

# Convert <dtok> to <tok> (to be dealt with later)
$scnt = 1;

$docid = $filename; $docid =~ s/.*\///; $docid =~ s/\.xml//;

print OUTFILE "# newdoc id = $docid";
$sents = $doc->findnodes("//s");
if ( !scalar $sents ) { $sents = $doc->findnodes("//u"); };
if ( $sents ) { 
	if ( $verbose ) { print "With sentences"; };
	$sntcnt = 1;
	foreach $snt ( @{$sents} ) {
		$sentid = $snt->getAttribute('id');
		if ( !$sentid ) { $sentid = "s-".$sntcnt++; $snt->setAttribute('id', $sentid); };
		$senttxt = $snt->textContent;
		$senttxt =~ s/\n/ /g; $senttext =~ s/ +/ /g;
		print OUTFILE "# sent_id = $docid\_$sentid";
		print OUTFILE "# text = $senttxt";
		undef(%toknrs); # Undef to avoid sentence-crossing links
		foreach $tok ( $snt->findnodes(".//tok") ) {
			$sentlines .= parsetok($tok);
		};
		print OUTFILE putheads($sentlines); 
		$sentlines = "";
		$toknr = 0;
	};
} else {
	if ( $verbose ) { print "Without sentences"; };
	$snum = 1;
	print OUTFILE "# sent_id = $docid\_s-".$snum++;
	foreach $tok ( $doc->findnodes("//tok") ) {
		if ( $newsent ) { 
			print OUTFILE "# sent_id s-".$snum++; 
			print OUTFILE "# text = $senttxt";
			print OUTFILE putheads($sentlines);
			$sentlines = ""; $senttxt = "";
			$toknr = 0;
		};
		$newsent = 0;
		@tmp = split("\t", $tokxml); 
		$tokxml = parsetok($tok); $sentlines .= $tokxml; 
		$senttxt .= $tmp[1]; if ( $tmp[9] !~ /Space/ ) { $senttxt .= " "; };
		if ( $tmp[1] =~ /^[.!?]$/ ) { 
			$newsent = 1;
		};
		$num++;
	};
	if ( $sentlines ) {
		print OUTFILE "# sent_id s-".$snum++; 
		print OUTFILE "# text = $senttxt";
		print OUTFILE putheads($sentlines);
		$sentlines = ""; $senttxt = "";
		$toknr = 0;
	};
};
print OUTFILE "\n";
close OUTFLE;

sub putheads($txt) {
	$txt = @_[0];

	while ( ( $key, $val) = each ( %toknrs ) ) {
		$txt =~ s/{#$key}/$val/g;
	};
	if ( $txt =~ /root/ ) {
		$txt =~ s/{#_}/0/g;
	} else {
		$txt =~ s/{#_}/_/g;
	};
	$txt =~ s/{#[wd][-0-9]+}/0/g; # Remove heads that did not get placed
	
	if ( $training ) { 
		# Remove all 0's that are not root when training
		$txt =~ s/^([^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+)\t0\t(?!root).*/\1\t0root/g;
	};
	
	return $txt;
};

sub parsetok($tk) {
	$tk = @_[0];

	$toklinenr = "";
	if ( !$tk->findnodes("./dtok") ) {
		$toknr++; 
		$toklinenr = $toknr;
		$tokid = $tk->getAttribute('id').'';
		$toknrs{$tokid} = $toknr;
		$word = calcform($tk, $wform);
		$word =~ s/\s+$//gsm;
		$word =~ s/&#039;/''/g;
		$lemma = $tk->getAttribute('lemma') or $lemma = "_";
		$xpos = $tk->getAttribute('xpos') or $xpos = $tk->getAttribute($posatt) or $xpos = "_";
		$upos = $tk->getAttribute('upos') or $upos = $xpos2upos{$xpos} or $upos = "_";
		$feats = $tk->getAttribute('feats') or $feats = $xpos2feats{$xpos} or $feats = "_";
		$head = $tk->getAttribute('head') or $head = "_";
		$deprel = $tk->getAttribute('deprel') or $deprel = "_";
		if ( $deprel eq '_' && $training ) { $deprel = "dep"; }; # We always need a deprel for training the parser
		$deps = $tk->getAttribute('deps') or $deps = "_";
		$misc = $tk->getAttribute('misc');
		if ( $misc ) { $misc = $misc."|"; };
		$misc .= $tokid; 
		
		# fallback
		if ( $word eq '' ) { $word = "_"; };
		if ( $misc eq '' ) { $misc = "_"; };
		
		undef($tkp); $tmp = $tk;
		if ( !$tk->nextSibling() ) { while ( $tmp->parentNode() &&  $tmp->parentNode()->getName() ne 's' ) { $tkp = $tmp->parentNode(); $tmp = $tkp; }; };
		if ( $tk->nextSibling() && $tk->nextSibling()->getName() eq "tok" ) { $misc .= "|SpaceAfter=No"; 
		} elsif ( $tkp && $tkp->nextSibling() && $tkp->nextSibling()->getName() eq "tok" ) { $misc .= "|SpaceAfter=No"; };

		$tokline = "\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\n";
	} else {
		$tokfirst = $toknr+1;
		$word = calcform($tk, $wform);
		$word =~ s/\s+$//gsm;
		$tokid = $tk->getAttribute('id').'';
		$misc = $tk->getAttribute('misc');
		if ( $misc ) { $misc = $misc."|"; };
		$misc .= $tokid; 

		if ( $word eq '' ) { $word = "_"; };
		if ( $misc eq '' ) { $misc = ""; };

		undef($tkp); $tmp = $tk;
		if ( !$tk->nextSibling() ) { while ( $tmp->parentNode() &&  $tmp->parentNode()->getName() ne 's' ) { $tkp = $tmp->parentNode(); $tmp = $tkp; }; };
		if ( $tk->nextSibling() && $tk->nextSibling()->getName() eq "tok" ) { $misc .= "|SpaceAfter=No"; 
		} elsif ( $tkp && $tkp->nextSibling() && $tkp->nextSibling()->getName() eq "tok" ) { $misc = "SpaceAfter=No"; };
		$tokline = "\t$word\t_\t_\t_\t_\t_\t_\t_\t$misc\n";
	};
	

	$dtoklines = "";
	foreach $dtk ( $tk->findnodes("./dtok") ) {
		$toknr++;
		$tokid = $dtk->getAttribute('id').'';
		$toknrs{$tokid} = $toknr;
		$word = calcform($dtk, $wform);
		$lemma = $dtk->getAttribute('lemma') or $lemma = "_";
		$upos = $dtk->getAttribute('upos') or $upos = "_";
		$xpos = $dtk->getAttribute('xpos') or $xpos = $dtk->getAttribute($posatt) or $xpos = "_";
		$feats = $dtk->getAttribute('feats') or $feats = "_";
		$head = $dtk->getAttribute('head') or $head = "_";
		$deprel = $dtk->getAttribute('deprel') or $deprel = "_";
		if ( $deprel eq '_' && $training ) { $deprel = "dep"; }; # We always need a deprel for training the parser
		$deps = $dtk->getAttribute('deps') or $deps = "_";
		$misc = $dtk->getAttribute('misc');
		if ( $misc ) { $misc = $misc."|"; };
		$misc .= $tokid;

		# fallback
		if ( $word eq '' ) { $word = "_"; };
		if ( $misc eq '' ) { $misc = "_"; };
		
		$dtoklines .= "$toknr\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\n";
	};
	if ( $toklinenr eq "" ) {
		$toklinenr = "$tokfirst-$toknr";
	};
	
	return "$toklinenr$tokline$dtoklines"; 
	
};

sub calcform ( $node, $form ) {
	( $node, $form ) = @_;
	
	if ( $form eq 'pform' ) {
		$value = $node->toString;
		$value =~ s/<\/?tok[^>]*>//g;
		return $value;
		# return $node->textContent;
	} elsif ( $node->getAttribute($form) ) {
		return $node->getAttribute($form);
	} elsif ( $inherit{$form} ) {
		return calcform($ttnode, $inherit{$form});
	} else {
		return "_";
	};
};