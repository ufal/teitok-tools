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
            'file=s' => \$filename, # input file name
            'output=s' => \$output, # output file name
            'folder=s' => \$folder, # Originals folder
            'pos=s' => \$posatt, # XPOS tag
            'tagmapping=s' => \$tagmapping, # XPOS tag
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

if ( !$posatt ) { $posatt = "pos"; };

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

print "Writing converted file to $output\n";
open OUTFILE, ">$output";
binmode(OUTFILE, ":utf8");

# Convert <dtok> to <tok> (to be dealt with later)
$scnt = 1;

$sents = $doc->findnodes("//s");
if ( $sents ) { 
	$sntcnt = 1;
	foreach $snt ( $doc->findnodes("//s") ) {
		$sentid = $snt->getAttribute('id');
		if ( !$sentid ) { $sentid = "s-".$sntcnt++; $snt->setAttribute('id', $sentid); };
		print OUTFILE "# sent_id $sentid";
		foreach $tok ( $snt->findnodes(".//tok") ) {
			$sentlines .= parsetok($tok);
		};
		print OUTFILE putheads($sentlines); 
		$sentlines = "";
		$toknr = 0;
	};
} else {
	$snum = 1;
	print OUTFILE "# sent_id s-".$snum++;
	foreach $tok ( $doc->findnodes("//tok") ) {
		if ( $newsent ) { 
			print OUTFILE "# sent_id s-".$snum++; 
			print OUTFILE putheads($sentlines);
			$sentlines = "";
			$toknr = 0;
		};
		$newsent = 0;
		$tokxml = parsetok($tok); $sentlist .= $tokxml;
		@tmp = split("\t", $tokxml); if ( $tmp[1] =~ /^[.!?]$/ ) { 
			$newsent = 1;
		};
		$num++;
	};
};
close OUTFLE;

sub putheads($txt) {
	$txt = @_[0];

	while ( ( $key, $val) = each ( %toknrs ) ) {
		$txt =~ s/{#$key}/$val/g;
	};
	$txt =~ s/{#_}/_/g;
	
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
		$word = $tk->getAttribute('nform') or $word = $tk->getAttribute('fform') or $word = $tk->getAttribute('form') or $word = $tk->textContent or $word = "_";
		$word =~ s/\s+$//gsm;
		$lemma = $tk->getAttribute('lemma') or $lemma = "_";
		$xpos = $tk->getAttribute('xpos') or $xpos = $tk->getAttribute($posatt) or $xpos = "_";
		$upos = $tk->getAttribute('upos') or $upos = $xpos2upos{$xpos} or $upos = "_";
		$feats = $tk->getAttribute('feats') or $feats = $xpos2feats{$xpos} or $feats = "_";
		$head = $tk->getAttribute('head') or $head = "_";
		$deprel = $tk->getAttribute('deprel') or $deprel = "_";
		$deps = $tk->getAttribute('deps') or $deps = "_";
		$misc = $tk->getAttribute('misc') or $misc = "_";
		
		if ( $tk->nextSibling() && $tk->nextSibling()->getName() eq "tok" ) { $misc = "SpaceAfter=No"; };

		$tokline = "\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\n";
	} else {
		$tokfirst = $toknr+1;
		$word = $tk->getAttribute('nform') or $word = $tk->getAttribute('fform') or $word = $tk->getAttribute('form') or $word = $tk->textContent or $word = "_";
		$word =~ s/\s+$//gsm;
		$tokline = "\t$word\t_\t_\t_\t_\t_\t_\t_\t_\n";
	};
	

	$dtoklines = "";
	foreach $dtk ( $tk->findnodes("./dtok") ) {
		$toknr++;
		$tokid = $dtk->getAttribute('id').'';
		$toknrs{$tokid} = $toknr;
		$word = $dtk->getAttribute('nform') or $word = $dtk->getAttribute('fform') or $word = $dtk->getAttribute('form') or $word = $dtk->textContent or $word = "_";
		$lemma = $dtk->getAttribute('lemma') or $lemma = "_";
		$upos = $dtk->getAttribute('upos') or $upos = "_";
		$xpos = $dtk->getAttribute('xpos') or $xpos = $dtk->getAttribute($posatt) or $xpos = "_";
		$feats = $dtk->getAttribute('feats') or $feats = "_";
		$head = $dtk->getAttribute('head') or $head = "_";
		$deprel = $dtk->getAttribute('deprel') or $deprel = "_";
		$deps = $dtk->getAttribute('deps') or $deps = "_";
		$misc = $dtk->getAttribute('misc') or $misc = "_";
		
		$dtoklines .= "$toknr\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\n";
	};
	if ( $toklinenr eq "" ) {
		$toklinenr = "$tokfirst-$toknr";
	};
	
	return "$toklinenr$tokline$dtoklines"; 
	
};
