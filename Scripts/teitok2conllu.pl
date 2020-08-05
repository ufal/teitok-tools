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
            'file=s' => \$filename, # which UDPIPE model to use
            'folder=s' => \$folder, # Originals folder
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename);
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };


( $outfile = $filename ) =~ s/\.xml/.conllu/;

print "Writing converted file to $outfile\n";
open OUTFILE, ">$outfile";
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
		$num = 1;
	};
} else {
	$snum = 1;
	print OUTFILE "# sent_id s-".$snum++;
	foreach $tok ( $xml->findnodes($tokxp) ) {
		if ( $newsent ) { 
			print OUTFILE "# sent_id s-".$snum++; 
			print OUTFILE putheads($sentlines);
			$sentlines = "";
		};
		$newsent = 0;
		$tokxml = parsetok($tok); $sentlist .= $tokxml;
		@tmp = split("\t", $tokxml); if ( $tmp[1] =~ /^[.!?]$/ ) { 
			$newsent = 1;
			$num = 0;
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
	$txt =~ s/{#_}/0/g;
	
	return $txt;
};

sub parsetok($tk) {
	$tk = @_[0];

	$toklinenr = "";
	if ( !$tk->findnodes("./dtok") ) {
		$toknr++; 
		$toklinenr = $toknr;
	} else {
		$tokfirst = $toknr+1;
	};
	
	$tokid = $tk->getAttribute('id').'';
	$toknrs{$tokid} = $toknr;
	$word = $tk->getAttribute('form') or $word = $tk->textContent or $word = "_";
	$lemma = $tk->getAttribute('lemma') or $lemma = "_";
	$upos = $tk->getAttribute('upos') or $upos = "_";
	$xpos = $tk->getAttribute('xpos') or $xpos = $tk->getAttribute('pos') or $xpos = "_";
	$feats = $tk->getAttribute('feats') or $feats = "_";
	$head = $tk->getAttribute('head') or $head = "_";
	$deprel = $tk->getAttribute('deprel') or $deprel = "_";
	$deps = $tk->getAttribute('deps') or $deps = "_";
	$misc = $tk->getAttribute('misc') or $misc = "_";

	$tokline = "\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\t$tokid\n";

	$dtoklines = "";
	foreach $dtk ( $tk->findnodes("./dtok") ) {
		$toknr++;
		$tokid = $dtk->getAttribute('id').'';
		$toknrs{$tokid} = $toknr;
		$word = $dtk->getAttribute('form') or $word = $dtk->textContent or $word = "_";
		$lemma = $dtk->getAttribute('lemma') or $lemma = "_";
		$upos = $dtk->getAttribute('upos') or $upos = "_";
		$xpos = $dtk->getAttribute('xpos') or $xpos = $dtk->getAttribute('pos') or $xpos = "_";
		$feats = $dtk->getAttribute('feats') or $feats = "_";
		$head = $dtk->getAttribute('head') or $head = "_";
		$deprel = $dtk->getAttribute('deprel') or $deprel = "_";
		$deps = $dtk->getAttribute('deps') or $deps = "_";
		$misc = $dtk->getAttribute('misc') or $misc = "_";
		
		$dtoklines .= "$toknr\t$word\t$lemma\t$upos\t$xpos\t$feats\t{#$head}\t$deprel\t$deps\t$misc\t$tokid\n";
	};
	if ( $toklinenr eq "" ) {
		$toklinenr = "$tokfirst-$toknr";
	};
	
	return "$toklinenr$tokline$dtoklines"; 
	
};
