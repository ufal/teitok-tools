use Getopt::Long;

# Convert CoNLL-U files into TEITOK/XML
# CoNLL-U is a syntactic annotation format developed for UD (https://universaldependencies.org/format.html)

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$debug, # debugging mode
            'file=s' => \$filename, # filename of the file to convert
            'output=s' => \$output, # filename of the output
            'outfolder=s' => \$outfolder, # filename of the output
            'morerev=s' => \$morerev, # language of input
            'split' => \$split, # Split into 1 file per # newdoc
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$outfolder && -e "xmlfiles" ) { $outfolder = "xmlfiles"; };
if ( !$output && $outfolder ) { $output = $outfolder."/".$basename.".xml"; };
if ( !$output && -e "xmlfiles" ) { $output = $basename.".xml"; };
if ( $outfolder ) { `mkdir -p $outfolder`; };

$teixml = conllu2tei($filename);

if ( $split && $indoc ) { 
	$output = $outfolder."/".$indoc;  
	if ( substr($output, -4) ne '.xml' ) { $output .= ".xml"; };
};
writeit($output, $teixml); # Write out (the remaining) XML lines


sub conllu2tei($fn) {
	$fn = @_[0]; $tokcnt = 1; %tok = (); %mtok = (); %etok = (); %etok = (); %sent = (); $scnt=1; $mtokcnt=1; $prevdoc = "";
	if ( $fn =~ /\/([a-z]+)_([a-z]+)-ud-([a-z]+).conllu/ ) { $lang = $1; $name = $2; $part = $3; };
	$linex = ""; 

	$/ = "\n";
	open FILE, $fn; $insent = 0; $inpar = 0; $indoc = 0; $doccnt =1;
	while ( <FILE> ) {	
		$line = $_; $line =~ s/[\n\r]//g;
		if ( $line =~ /# newdoc id = (.*)/ || $line =~ /# newdoc/ ) {
			$doccnt++;
			$newdoc = $1 or $newdoc = "doc$doccnt";
			$newdoc =~ s/\//_/g;
			if ( $debug ) { print " - begin of newdoc $indoc ; $line"; };
			if ( $inpar ) { $linex .= "</p>\n"; $inpar = 0; }; # A new document always closes the paragraph
			if ( $split ) {
				if ( $indoc ) { 
					$outfile = $outfolder."/".$indoc;
					if ( substr($outfile, -4) ne '.xml' ) { $outfile .= ".xml"; };
					writeit($outfile, $linex); 
					$linex = "";
				}; 
			} else {
				if ( $indoc ) { $linex .= "</doc>\n"; }; 
				$linex .= "<doc id=\"$indoc\">\n"; 
			};
			$indoc = $newdoc;
		} elsif ( $line =~ /# newpar id = (.*)/ || $line =~ /# newpar/ ) {
			if ( $inpar ) { $linex .= "</p>\n"; };
			$linex .= "<p org_id=\"$1\">\n"; 
			$inpar = 1;
		} elsif ( $line =~ /# ?([a-z0-9A-Z\[\]¹_-]+) ?=? (.*)/ ) {
			$sent{$1} = $2;
		} elsif ( $line =~ /^(\d+)\t(.*)/ ) {
			$tok{$1} = $2; $tokmax = $1; 
			$tokid{$1} = $tokcnt++;	
		} elsif ( $line =~ /^(\d+)-(\d+)\t(.*)/ ) {
			# To do : mtok / dtok	
			$mtok{$1} = $3; $etok{$2} = $3; $mtoke{$1} = $2;
		} elsif ( $line =~ /^(\d+\.\d+)\t(.*)/ ) {
			# To do : non-word tokens; ignore for now (extended trees - only becomes relevant if UD integration stronger)
		} elsif ( $line =~ /^#/ ) {
			# To do : ??	
		} elsif ( $line eq '' ) {
			$linex .= makesent(%sent, %tok);
			%tok = (); %mtok = ();  %etok = ();  %tokid = ();  %sent = ();
		} else {
			print "What? ($line)"; 
		};
	};
	if ( keys %sent ) { $linex .= makesent(%sent, %tok); }; # Add the last sentence if needed
	if ( $inpar ) { $linex .= "</p>\n"; };
	if ( !$split && $indoc ) { $linex .= "</doc>\n"; };

	return $linex;
		
};

sub makesent($sent, $tok) {
	( $sent, $tok ) = @_;
	
	if ( !scalar $tok) { return; };
	
	$moresf = "";
	while ( ( $key, $val ) = each (%sent) ) { 
		$att = $key; $att =~ s/\[/_/g; $att =~ s/[^a-z_0-9]//g;
		if ( $att ne 'id' && $att ne '' ) { $moresf .= " $att=\"".textprotect($val)."\""; };
	};
	$sentxml = "<s id=\"s-".$scnt++."\" $moresf>"; $dtokxml = "";
	for ( $i=1; $i<=$tokmax; $i++ ) {
		$tokline = textprotect($tok{$i}); $headf = "";
		( $word, $lemma, $upos, $xpos, $feats, $head, $deprel, $deps, $misc ) = split("\t", $tokline ); 
		if ( $head && $head ne '' && $head ne '_' ) { $headf = "head=\"w-".$tokid{$head}."\""; };
		if ( $mtok{$i} ) { 
			( $mword, $mlemma, $mupos, $mxpos, $mfeats, $mhead, $mdeprel, $mdeps, $mmisc ) = split("\t", $mtok{$i}); 
			if ( $mword =~ / / ) {
				$sentxml .= "<mtok id=\"w-".$mtok++."\" form=\"$mword\" lemma=\"$mlemma\" upos=\"$mupos\" xpos=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" ord=\"$i\" ohead=\"$head\" deps=\"$deps\" misc=\"$misc\" $mheadf>";			
			} else {
				$dtokxml = "<tok id=\"w-".$tokid{$i}."\" lemma=\"$mlemma\" upos=\"$mupos\" xpos=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" ord=\"$i\" ohead=\"$head\" deps=\"$mdeps\" misc=\"$mmisc\" $mheadf>$mword";			
			};
		}		
		if ( $dtokxml ) {
			$dtokxml .= "<dtok id=\"w-".$tokid{$i}."\" lemma=\"$lemma\" upos=\"$upos\" xpos=\"$xpos\" feats=\"$feats\" deprel=\"$deprel\" ohead=\"$head\" ord=\"$i\" deps=\"$deps\" misc=\"$misc\" $headf form=\"$word\"/>";			
		} else {
			$tokxml = "<tok id=\"w-".$tokid{$i}."\" lemma=\"$lemma\" upos=\"$upos\" xpos=\"$xpos\" feats=\"$feats\" deprel=\"$deprel\" ohead=\"$head\" ord=\"$i\" misc=\"$misc\" $headf>$word</tok>";
			$tokxml =~ s/ [a-z]+="_"//g; # Remove empty attributes
			$sentxml .= $tokxml;
			if ( $misc !~ /SpaceAfter=No/ ) { $sentxml .= " "; }; # Add a space unless told not to
		};
		if ( $etok{$i} ) {
			if ( $dtokxml ) {
				$dtokxml .= "</tok>";
				$sentxml .= $dtokxml;		
				if ( $nsp !~ /SpaceAfter=No/ ) { $sentxml .= " "; }; # Add a space unless told not to (does that work with spans?)
				$dtokxml = "";
			} else {
				$sentxml .= "</mtok>";			
			};
		};
	}; 
	$sentxml .= "</s>\n"; 
	
	return $sentxml;
};

sub textprotect ( $text ) {
	$text = @_[0];
	
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g; 
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&#039;/g;

	return $text;
};

sub writeit($outfile = $output) {
	( $outfile, $teixml ) = @_;
	print "Writing output to $outfile";
	open OUTFILE, ">$outfile";
	print OUTFILE "<TEI>
	<teiHeader>
		<notesStmt><note n=\"orgfile\">$basename.conllu</note></notesStmt>
		<revisionDesc><change who=\"conllu2teitok\" when=\"$now\">Converted from CoNLL-U $filename</change></revisionDesc>
	</teiHeader>
	<text>
	$teixml
	</text>
	</TEI>";
	close OUTFILE;
};
