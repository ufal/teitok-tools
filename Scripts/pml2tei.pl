use Getopt::Long;
use XML::LibXML;

# Convert PML files to TEITOK/XML
# PML is the file format developed for the Prague Dependency Treebank
 
 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'file=s' => \$filename, # language of input
            'output=s' => \$output, # language of input
            'morerev=s' => \$morerev, # language of input
            );

$\ = "\n"; $, = "\t";


if ( !$filename ) { $filename = shift; };
if ( $filename =~ /\.[amw]$/ ) { $filename =~ s/\..+?$/.w/; };
if ( !$output ) { ( $output = $filename ) =~ s/\..+?$/.xml/; };

( $p1, $p2, $p3, $ann, $subset, $fn ) = split ( "/", $filename );
$localmeta .= "";
	
	$/ = undef;
	open FILE, $filename;
	$raw = <FILE>;
	close FILE;
	
if ( $raw =~ /<othermeta origin="([^"]+)">(.*)<\/othermeta>/smi ) {	
	$localmeta .= " origin=\"$1\"";
	$other = $2;
	while ( $other =~ /&lt;([^>]+)>(.+)/g ) {
		$localmeta .= " $1=\"$2\"";
	};
};
if ( $raw =~ /<original_format>([^><]+)<\/original_format>/ ) { $localmeta .= " original_format=\"$1\""; };
if ( $raw =~ /<doc([^>]+)>/ ) { $docmeta = $1; };

	$raw =~ s/.*?<doc>//smi;
	$raw =~ s/\n\s*<\/doc>.*//smi;
	$raw =~ s/<docmeta>.*?<\/docmeta>.*//smi;
	$raw =~ s/\n\s*<token>(.*)<\/token>\n\s*/\1/gmi;
	$raw =~ s/>([^><]+)<no_space_after>1<\/no_space_after>\n\s*<\/w>\n\s*<w / glue="1">\1<\/tok><w /gmi;
	$raw =~ s/<w id=/<tok pdtid=/g;
	$raw =~ s/<para>\n\s*<othermarkup origin="csts\/doc\/p\/\@n">(\d+)<\/othermarkup>/<p n="\1">xx/gsmi;
	$raw =~ s/<\/w>/<\/tok>/g;
	$raw =~ s/<\/para>/<\/s>\n  <\/p>/g;
	$raw =~ s/(<tok pdtid="[^"]+w1")/\n  <\/s>\n  <s>\n   \1/gsmi;
	$raw =~ s/xx\n\s*\n\s*<\/s>//gsmi;
	
	( $rfname = $filename ) =~ s/.*\///;
	$tei = "<TEI>
<teiHeader>
	<notesStmt>
		<note n=\"orgfile\">$rfname<\/note>
		<note n=\"localmeta\" $localmeta/>
		<note n=\"subcorpus\" ann=\"$ann\" subset=\"$subset\"/>
	</notesStmt>	
<revisionDesc>
	$morerev<change who=\"pml2tei\" when=\"$today\">Converted from PML</change></revisionDesc>
</teiHeader>
<text$docmeta>
$raw
</text>
</TEI>";

# Check if this is valid XML to start with
$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(string => $tei);
};
if ( !$doc ) { 
	print "Created invalid XML";
	open FILE, ">tmp/wrong.xml";
	print FILE $tei;
	close FILE; 
	exit;
};

( $tmp = $filename ) =~ s/\.w$//;	
# treat w
	if ( -e $tmp.".w" ) {
		open FILE, $tmp.".w";
		$xml = <FILE>;
		close FILE;
		$xml =~ s/xmlns/xmlnsoff/g;
		$wdoc = $parser->load_xml(string => $xml);
	};
	
# treat m
	if ( -e $tmp.".m" ) {
		if ( $debug ) { print "Found m-layer:  $tmp.m"; };
		open FILE, $tmp.".m";
		$xml = <FILE>;
		close FILE;
		$xml =~ s/xmlns/xmlnsoff/g;
		$mdoc = $parser->load_xml(string => $xml);
	};
	
# treat a
	if ( -e $tmp.".a" ) {
		if ( $debug ) { print "Found m-layer:  $tmp.a"; };
		open FILE, $tmp.".a";
		$xml = <FILE>;
		close FILE;
		$xml =~ s/xmlns/xmlnsoff/g;
		$adoc = $parser->load_xml(string => $xml);
	};
	
# treat t
	if ( -e $tmp.".t" ) {
		if ( $debug ) { print "Found t-layer:  $tmp.t"; };
		open FILE, $tmp.".t";
		$xml = <FILE>;
		close FILE;
		$xml =~ s/xmlns/xmlnsoff/g;
		$tdoc = $parser->load_xml(string => $xml);
	};
	
$tid = 0;
foreach $tok ( $doc->findnodes("//tok") ) {
	$tid++; $tok->setAttribute('id', 'w-'.$tid);
	$pdtid = $tok->getAttribute('pdtid'); $mid = undef;
	if ( $debug ) { print $pdtid, $tok->textContent; };
	$w2tei{$pdtid} = 'w-'.$tid;
	
	# Deal with the M layer
	if ( $mdoc ){
		$mx = "//LM[text()='w#$pdtid']/../..";
		@tmp = $mdoc->findnodes($mx);
		$mnode = $tmp[0];
		if ( $m2w{$pdtid} && 1==2 ) {	
			print "-- Duplicate M token: ".$tok->toString;
		} elsif ( scalar @tmp > 1 ) {
			if ( $debug  ) { print "-- MTOK: ".$tok->toString; };
			for ( $i=0; $i< scalar @tmp; $i++ ) {
				$mid = $tmp[$i]->getAttribute('id');
				$dtok = $doc->createElement('dtok');
				$did = "d-$tid-".($i+1);
				$dtok->setAttribute('id', $did);
				$dtok->setAttribute('pdtid', $mid);
				$form = $tmp[$i]->findnodes("./form")->item(0)->textContent;
				$dtok->setAttribute('form', $form);
				$lemma = $tmp[$i]->findnodes("./lemma")->item(0)->textContent;
				$more = $sub = "";
				if ( $lemma =~ /^(.*)_(.*)$/ ) {
					$lemma = $1; $more = $2;
					$dtok->setAttribute('lemsem', $more);
				};
				if ( $lemma =~ /^(.*)-(\d+)$/ ) {
					$lemma = $1; $sub = $2;
					$dtok->setAttribute('lemsub', $sub);
				};
				$dtok->setAttribute('lemma', $lemma);
				$pos = $tmp[$i]->findnodes("./tag")->item(0)->textContent;
				if ( $debug ) {  print "- $lemma, $pos $more $sub"; };
				$dtok->setAttribute('pos', $pos);
				$tok->appendChild($dtok);
				$m2w{$mid} = $mid;
				$w2m{$mid} = $mid;
				$w2tei{$mid} = $did;
			};
		} elsif ( $mnode ) {
			$mid = $mnode->getAttribute('id');
			$lemma = $mnode->findnodes("./lemma")->item(0)->textContent;
			$more = $sub = "";
			if ( $lemma =~ /^(.*?)_(.*)$/ ) {
				$lemma = $1; $more = $2;
				$tok->setAttribute('lemsem', $more);
			};
			if ( $lemma =~ /^(.*)-(\d+)$/ ) {
				$lemma = $1; $sub = $2;
				$tok->setAttribute('lemsub', $sub);
			};
			$pos = $mnode->findnodes("./tag")->item(0)->textContent;
			if ( $debug ) {  print "- $lemma, $pos $more $sub"; };
			$tok->setAttribute('lemma', $lemma);
			$tok->setAttribute('pos', $pos);
			$m2w{$mid} = $pdtid;
			$w2m{$pdtid} = $mid;
		} else {
			print "-- Extra token: ".$tok->toString;
		};
	};
};

# Number the s	
$tid = 0;
foreach $tok ( $doc->findnodes("//s") ) {
	$tid++; $tok->setAttribute('id', 's-'.$tid);
};

if ( $adoc ) {

	# Deal with the A layer
	foreach $tok ( $doc->findnodes("//tok[not(dtok)] | //dtok") ) {
		$pdtid = $tok->getAttribute('pdtid');
		$mid = $w2m{$pdtid};
		if ( $adoc && $mid ) {
			$ax = "//m.rf[.='m#$mid']/..";
			@tmp = $adoc->findnodes($ax);
			$anode = $tmp[0];
			if ( $a2m{$pdtid} ) {	
				print "-- Duplicate A token: ($pdtid) ".$tok->toString;
			} elsif ( $anode ) {
				$aid = $anode->getAttribute('id');
				if ( $debug ) { print $mid, $aid; };
				$deprel = $anode->findnodes("./afun")->item(0)->textContent;
				$parid = $anode->findnodes("../../\@id")->item(0)->value;
				if ( $debug ) {  print "- (head) $parid, $deprel"; };
				$tok->setAttribute('pdthead', $parid);
				$tok->setAttribute('deprel', $deprel);
				$a2m{$aid} = $mid;
				$m2a{$mid} = $aid;
			} else {
				print "-- Extra token: ".$mnode->toString;
			};
		};	
	};

	# Number the heads	
	foreach $tok ( $doc->findnodes("//tok[not(dtok)] | //dtok") ) {
		$pdtheadid = $tok->getAttribute('pdthead');
		if ( $pdtheadid ) {
			if ( $debug ) { print $tok->getAttribute('id'), $pdtheadid, $a2m{$pdtheadid}, $m2w{$a2m{$pdtheadid}}, $w2tei{$m2w{$a2m{$pdtheadid}}};		 };
			$headid = $w2tei{$m2w{$a2m{$pdtheadid}}};
			if ( $headid ne '' ) {
				$tok->setAttribute('head', $headid);		
			} elsif ( $pdtheadid =~ /w\d+/ ) {
				print "No head found: $pdtheadid = ".$a2m{$pdtheadid}." < ".$m2w{$a2m{$pdtheadid}};
			};
		} else {
			print "No pdtheadid: ".$tok->toString;
		};
	};

};

if ( $tdoc ) {
	foreach $tok ( $doc->findnodes("//tok[not(dtok)] | //dtok") ) {
		$pdtid = $tok->getAttribute('pdtid');
		$aid = $m2a{$w2m{$pdtid}};
		if ( $tdoc && $aid ) {
			$tx = "//lex.rf[text()='a#$aid']/../..";
			@tmp = $tdoc->findnodes($tx);
			$tnode = $tmp[0];
			if ( $tnode ) {
				@tmp2 = $tnode->findnodes("./tfa");
				if ( @tmp2 ) { 
					$tfa = $tmp2[0]->textContent;
					$tok->setAttribute('tfa', $tfa);
				};
				@tmp2 = $tnode->findnodes("./gram/sempos");
				if ( @tmp2 ) { 
					$sempos = $tmp2[0]->textContent;
					$tok->setAttribute('sempos', $sempos);
				};
				@tmp2 = $tnode->findnodes("./val_frame.rf");
				if ( @tmp2 ) { 
					( $vallex = $tmp2[0]->textContent ) =~ s/^v#//;
					$tok->setAttribute('vallex', $vallex);
				};
				@tmp2 = $tnode->findnodes("../../\@id");
				if ( @tmp2 ) {
					$pdttheadid = $tmp2[0]->value;
					if ( $debug ) {  print "- (head) $parid, $deprel"; };
					$tok->setAttribute('pdtthead', $pdttheadid);
				} else { print "No t-head: $pdtid / $aid"; exit; };
				if ( $debug ) { print "T Level: $tfa, $sempos, $vallex".$tok->toString; };
			};
		};
	};

	# Number the heads	
	foreach $tok ( $doc->findnodes("//tok[not(dtok)] | //dtok") ) {
		$pdtheadid = $tok->getAttribute('pdtthead');
		if ( $pdtheadid ) {
			if ( $debug ) { print $tok->getAttribute('id'), $pdtheadid, $a2m{$pdtheadid}, $m2w{$a2m{$pdtheadid}}, $w2tei{$m2w{$a2m{$pdtheadid}}};		 };
			$headid = $w2tei{$m2w{$a2m{$t2a{$pdtheadid}}}};
			if ( $headid ne '' ) {
				$tok->setAttribute('thead', $headid);		
			} elsif ( $pdtheadid =~ /w\d+/ ) {
				print "No head found: $pdtheadid = ".$t2a{$pdtheadid}." < ".$a2m{$pdtheadid}." < ".$m2w{$a2m{$pdtheadid}};
			};
		} else {
			print "No pdtheadid: ".$tok->toString;
		};
	};
};

if ( $debug ) {
	print $doc->toString; 
	exit;
};

if ( $filename =~ /.*\/([^.\/]+)\.w/ ) { $xmlid = $1; };
open FILE, ">$output";
print "Writing output to $output";
print FILE $doc->toString;
close FILE;