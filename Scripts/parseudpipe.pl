use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Parse a tokenized TEITOK file using UDPIPE
# UDPIPE (https://lindat.mff.cuni.cz/services/udpipe/) is a dependency parser using Universal Dependencies

$scriptname = $0;

GetOptions ( ## Command line options
            'verbose' => \$verbose, # debugging mode
            'debug' => \$debug, # debugging mode
            'nocheck' => \$nocheck, # assume all checks pass
            'writeback' => \$writeback, # write back to original file or put in new file
            'file=s' => \$file, # file to tag
            'force' => \$force, # force even if alrady tagged
            'extfile=s' => \$extfile, # use an external file as parsed CoNLL-U
            'modfolder=s' => \$modfolder, # file to tag
            'model=s' => \$model, # which UDPIPE model to use
            'lang=s' => \$lang, # language of the texts (if no model is provided)
            'folder=s' => \$folder, # Originals folder
            'token=s' => \$token, # token node
            'xpos=s' => \$xpostag, # attribute to use for XPOS
            'tokxp=s' => \$tokxp, # token XPath
            'sent=s' => \$sent, # sentence node
            'sentxp=s' => \$sentxp, # sentence XPath
            'atts=s' => \$atts, # attributes to use for the word form
            'forms=s' => \$atts, # attribute for the normalized form
            'mode=s' => \$mode, # how to run UDPIPE (server or local - when /usr/local/bin/udpipe)
            'force' => \$force, # run without checks
            'task=s' => \$task, # run as tagger / parser
            'token=s' => \$udptok, # use a login token for UDPIPE (billing)
            'url=s' => \$url, # URL to use to "UDPIPE" (billing)
            'emptys' => \$emptys, # keep <s> nodes as empty nodes (with a @corresp)
            'modelroot=s' => \$modelroot, # folder where the models are
            'nocheck' => \$nocheck, # run the model, do not check if it exists
            );

$\ = "\n"; $, = "\t";

$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
$parser = XML::LibXML->new(); 

if ( $debug ) { $verbose = 1; };
if ( !$token ) { 
	$token = "tok"; 
};
if ( !$tokxp ) {
	$tokxp = "//tok[not(dtok)] | //dtok"; 
};
if ( !$atts ) { $atts = "nform,reg,fform,expan,form"; };
if ( !$xpostag ) { $xpostag = "xpos"; };

if ( !$file ) { $file = shift; };
if ( !$mode ) { $mode = "server"; };

if ( $extfile ) {
	if ( $verbose ) { print "Taking input from: $extfile"; };
	$/ = undef;
	open FILE, $file;
	binmode (FILE, ":utf8");
	$rawxml = <FILE>;
	close FILE;
	$rawxml =~ s/xmlns=/xmlnstmp=/;
	eval {
		$xml = $parser->load_xml(string => $rawxml, load_ext_dtd => 0);
	};
	foreach $tok ( $xml->findnodes($tokxp) ) {
		$tokid = $tok->getAttribute('id').'';
		$tokhash{$tokid} = $tok;
	};
	parseconllu($extfile);
	
	# Add the revision statement
	$revnode = makenode($xml, "/TEI/teiHeader/revisionDesc/change[\@who=\"conllu\"]");
	$when = strftime "%Y-%m-%d", localtime;
	$revnode->setAttribute("when", $when);
	$revnode->appendText("loaded parsing data from $extfile");
	
	if ( $writeback ) { 
		$outfile = $file;
	} else {
		( $outfile = $file ) =~ s/udpipe/parsed/;
		$outfile =~ s/\.conllu$/\.xml/;
		( $tmp = $outfile ) =~ s/\/[^\/]+$//;
		`mkdir -p $tmp`;
	};
	if ( $verbose ) { print "Writing parsed file to $outfile\n"; };

	$rawxml = $xml->toString;
	$rawxml =~ s/xmlnstmp=/xmlns=/;

	open OUTFILE, ">$outfile";
	# binmode (OUTFILE, ":utf8");	# TODO: Is this ever needed?	
	print OUTFILE $rawxml;	
	close OUTFLE;

	exit;
};

if ( $mode eq "local" ) {

	( $tmp = $0 ) =~ s/Scripts.*/Resources\/udpipe-models.txt/;
	open FILE, $tmp; %udm = ();
	while ( <FILE> ) {
		chop;
		( $iso, $code, $lg, $mod ) = split ( "\t" );
		$code2model{$code} = $mod;
		$code2model{$iso} = $mod;
		$lang2model{$lg} = $mod;
		$mod2lang{$mod} = ucfirst($lg);
		$mod2code{$mod} = $code;
		$models{$mod} = 1;
	}; 
	if ( !$model ) {
		if ( $lang ) { 
			$model = $code2model{$lang} or $model = $lang2model{lc($lang)};
			if ( !$model ) { print "No UDPIPE models for $lang"; exit; };
			if ( $verbose ) { print "Choosing $model for $lang"; };
		};
	} elsif ( !$models{$model} && !$force && !$nocheck ) { print "No such UDPIPE model: $model"; exit;  };

	if ( $verbose && !$nocheck ) { print "Using model: $model"; };

} else {

	if ( $verbose && $model ) { print "Using model: $model"; }
	elsif ( $verbose && $lang ) { print "Using language: $lang"; };

};


if ( !$writeback) { mkdir($tmpf."udpipe"); };
@formatts = split( ",", $atts );

if ( $file ) {
	if ( !-e $file ) { print "No such file: $file"; exit; };
	treatfile($file);
} elsif ( $folder ) { 
	if ( !-d $folder ) { print "No such folder: $folder"; exit; };
	find({ wanted => \&treatfile, follow => 1, no_chdir => 1 }, $folder);
} else {
	print "Please provide a file or folder to parse"; exit;
};

STDOUT->autoflush();

sub treatfile ( $fn ) {
	$tokcnt = 1;
	$fn = $_; if ( !$fn ) { $fn = @_[0]; }; $orgfile = $fn;
	if ( !-d $fn ) { 
		if ( $verbose ) { print "\nTreating $fn"; };
	
		$/ = undef;
		open FILE, $fn;
		binmode (FILE, ":utf8");
		$rawxml = <FILE>;
		close FILE;
		
		# read the XML
		if ( !$tokxp ) { $tokxp = "//$token"; };
		( $reltokxp = $tokxp ) =~ s/(^| )\/\//\1.\/\//g;

		if ( $rawxml =~ / upos=/ && !$force ) {
			print "$fn: already parsed";
			return -1;
		};
		
		if ( $rawxml !~ /<\/$token>/  ) {
			print "Not tokenized - tokenizing";
			( $tokr = $scriptname ) =~ s/parseudpipe/xmltokenize/;
			$cmd = "perl $tokr --sent=2 $fn";  
			print $cmd;
			`$cmd`;
			open FILE, $fn;
			binmode (FILE, ":utf8");
			$rawxml = <FILE>;
			close FILE;
		};
		
		$rawxml =~ s/xmlns=/xmlnstmp=/;
		eval {
			$xml = $parser->load_xml(string => $rawxml, load_ext_dtd => 0);
		};
		if ( !$xml ) { 
			print "Invalid XML in $fn";
			open FILE, ">wrong.xml";
			print FILE $rawxml;
			close FILE;
			return -1;
		};
		
		if ( !$nocheck ) {
		if ( $noid = $xml->findnodes("//tok[not(\@id)] | //dtok[not(\@id)]") ) {
			$tokcnt = scalar @{$xml->findnodes("//".$token."[\@id]")};
			if ( $verbose ) {  print "There are unnumbered (d)toks - renumbering"; };
			foreach $node ( @{$noid} ) {
				$nn = $node->nodeName();
				if ( $nn eq 'tok' ) {
					$newid = "w-".++$tokcnt;
				} elsif ( $nn eq 'dtok' ) {
					$tokid = $node->parentNode->getAttribute('id');
					$newid = $tokid;
					$newid =~ s/w-/d-/;
					$dcnt{$tokid}++; 
					$newid .= "-".$dcnt{$tokid}; 
				} else { print "??$nn"; };
				if ( $newid ) { $node->setAttribute('id', $newid); };
				if ( $debug ) { print "Set new ID for $nn to $newid"; };
			};
		};};

		if ( $verbose ) { print "\nExporting to CoNLL-U"; };
		
		$num = 1; 
		if ( $sent || $sentxp ) { 
			$sntcnt = 1;
			if ( !$sentxp ) { $sentxp = "//$sent"; };
			foreach $snt ( $xml->findnodes($sentxp) ) {
				$sentid = $snt->getAttribute('id');
				if ( !$sentid ) { $sentid = "s-".$sntcnt++; $snt->setAttribute('id', $sentid); };
				$toklist .= "# sent_id $sentid\n";
				foreach $tok ( $snt->findnodes($reltokxp) ) {
					$tokxml = parsetok($tok);
					$tokid = $tok->getAttribute('id').'';
					$tokhash{$tokid} = $tok;
					$toklist .= $tokxml;
					@tmp = split("\t", $tokxml); 
					$rawtxt .= $tmp[1]." ";
					$num++;
				};
				$toklist .= "\n"; $num = 1;
			};
		} else {
			$snum = 1; 
			if ( !$xml->findnodes("//text//s") ) { $mansent = 1; };
			$toklist = "# sent_id s-".$snum++."\n";
			if ( !$pelms ) { $pelms = "p,head,tei_head,div,tei_div,speaker,u,text"; };
			foreach $pelm ( split(",", $pelms) ) {
				$pxp = "//text//$pelm\[.//tok]";
				@ps = $xml->findnodes($pxp);
				foreach $pp ( @ps ) {
					$ftok = $pp->findnodes(".//tok")->item(0);
					$ftid = $ftok->getAttribute("id");
					if ( $debug ) { print "First in $pelm: $ftid"; };
					$pfirst{$ftid} = 1;
				};
			};
			@atoks = $xml->findnodes($tokxp);
			$tn = 0;
			foreach $tok ( @atoks ) {
				$tokid = $tok->getAttribute('id').'';
				if ( $pfirst{$tokid} ) { 
					$toklist .= "\n"; 
					$num = 1;
					$newsent = 1; 
				};
				if ( $newsent ) { $toklist .= "# sent_id s-".$snum++."\n"; };
				$newsent = 0;
				$tokxml = parsetok($tok); 
				$tokhash{$tokid} = $tok;
				$toklist .= $tokxml;
				$cnt++; 
				@tmp = split("\t", $tokxml); 
				$rawtxt .= $tmp[1]." ";
				if ( $tmp[1] =~ /^[.!?]$/ ) { 
					$chk = ""; if ( $atoks[($tn+1)] ) { $chk = $atoks[($tn+1)]->textContent; };
					if ( !$chk || $chk !~ /^[.!?]$/ ) { # Do not insert a new sent in ?!?!?
						$newsent = 1;
					};
				};
				if ( $newsent ) {
					$toklist .= "\n"; 
					$num = 0;
				};
				if ( $tokxml ne '' ) { $num++; $tn++; };
			};
		};
		utf8::upgrade($toklist);
		
		if ( $debug ) { print "$cnt tokens to be submitted to UDPIPE:"; };

		if ( !$model && !$lang ) {
			$tmp = $xml->findnodes("//langUsage/language/\@ident");
			if ( $tmp ) { $lang = $tmp->item(0)->value; }
			elsif ( $verbose ) { print "No language/@ident in teiHeader"; };
		};
		
		if ( !$model && !$lang ) {
			$lang = detectlang($rawtxt);
			$model = $code2model{$lang};
			if ( $verbose ) { print "Detected language : $lang => $model"; };
			if ( !$model ) { print "No UDPIPE models for $lang"; exit; };
		};
	
		if ( $debug ) { 
			binmode(STDOUT, ":utf8");
			print $toklist; 
		};
				
		$udfile = $fn;
		if ( $folder eq '' ) { $udfile = "udpipe/$udfile"; };
		$udfile =~ s/\.[^.]+$/\.conllu/;
		( $tmp = $udfile ) =~ s/\/[^\/]+$//;
		`mkdir -p $tmp`;
		$conllu = runudpipe($toklist, $model, $udfile);
		
		parseconllu($udfile);		
		
		if ( !$usedmodel ) { $usedmodel = $model; }; # Try to always use the model read from conllu
		if ( $verbose && $nocheck ) { print "Used model: $usedmodel"; };
		
		# Add the revision statement
		$revnode = makenode($xml, "/TEI/teiHeader/revisionDesc/change[\@who=\"udpipe\"]");
		$when = strftime "%Y-%m-%d", localtime;
		$revnode->setAttribute("when", $when);
		$revnode->appendText("parsed with UDPIPE using $usedmodel");
		
		if ( $writeback ) { 
			$outfile = $orgfile;
		} else {
			( $outfile = $udfile ) =~ s/udpipe/parsed/;
			$outfile =~ s/\.conllu$/\.xml/;
			( $tmp = $outfile ) =~ s/\/[^\/]+$//;
			`mkdir -p $tmp`;
		};
		if ( $verbose ) { print "Writing parsed file to $outfile\n"; };

		$rawxml = $xml->toString;
		$rawxml =~ s/xmlnstmp=/xmlns=/;

		open OUTFILE, ">$outfile";
		# binmode (OUTFILE, ":utf8"); # This is not needed since it should not be "proper" UTF8 
		print OUTFILE $rawxml;	
		close OUTFLE;
		
	};
};

sub parsetok ($tok) { 
	$tokid = $tok->getAttribute('id');
	if ( !$tokid ) { $tokid = "w-".$tokcnt++; $tok->setAttribute('id', $tokid); };
	$form = "";
	foreach $att ( @formatts ) {
		$form = $tok->getAttribute($att);
		if ( $form ) { last; }
	};
	if ( !$form ) { $form = $tok->textContent; };
	if ( !$form ) { return ""; };	
	
	if ( $task eq 'parse' ) {
		$lemma = $tok->getAttribute('lemma') or $lemma = "_";
		$upos = $tok->getAttribute('upos') or $upos = "_";
		$xpos = $tok->getAttribute($xpostag) or $xpos = "_";
		$feats = $tok->getAttribute('feats') or $feats = "_";
	} else {
		$lemma = $upos = $xpos = "_";
	};
	if ( $feats eq '' ) { $feats = "_"; };
	if ( $lemma eq '' ) { $lemma = "_"; };
	if ( $upos eq '' ) { $upos = "_"; };
	if ( $xpos eq '' ) { $xpos = "_"; };
	
	$form =~ s/^\s*|\s*$//gsmi;
	if ( $form eq '_' || $form eq '' ) { return ""; }; # No empty strings in CONLL-U
	
	return "$num\t$form\t$lemma\t$upos\t$xpos\t$feats\t_\t_\t_\t$tokid\n"; $num++;
};

sub detectlang ( $text ) {
	$text = @_[0];
	%form = (
		"data" => $text
	);
	
	$url = 'http://quest.ms.mff.cuni.cz/teitok-dev/teitok/cwali/index.php?action=cwali';
	$res = $ua->post( $url, \%form );
	$jsdat = $res->decoded_content;
	eval {
		$jsonkont = decode_json($jsdat);
	};
	if ( !$jsonkont ) {
		print "Error: failed to get language data back from CWALI";
		return "xxx";
	};
	$iso = $jsonkont->{'best'}; $name = $jsonkont->{'name'};
	$model = $code2model{$iso} or $model = $lang2model{$name}; 
	if ( $verbose ) { print " - Language detected: $iso / $name, using $model"; };
	
	return $iso;
};

sub runudpipe ( $raw, $model, $udfile ) {
	($raw, $model) = @_;

	if ( $task eq 'parse' ) { 
		$modes = "--parse";
		$totag = 0; $toparse = 1;
	} elsif ( $task eq 'tag' ) {
		$modes = "--tag";
		$totag = 1; $toparse = 0;
	} else {
		$modes = "--tag --parse";
		$totag = 1; $toparse = 1;
	};

	if ( -e "/usr/local/bin/udpipe" && $mode eq 'local' ) {
		
		if ( !$modelroot ) { ( $modelroot = $scriptname ) =~ s/\/[^\/]+$//; };
		if ( -e "$modelroot/$model" ) {
			$modelfile = "$modelroot/$model";
		} else {
			$modelfile = `locate $model`; chop($modelfile);
		};

		($tmpfile = $udfile) =~ s/\./-vrt./;
		open FILE, ">$tmpfile";
		binmode (FILE, ":utf8");
		print FILE $raw;
		close FILE;
		
		if ( $verbose ) { print " - Writing VRT file to $tmpfile"; };
		$cmd = "/usr/local/bin/udpipe $modes --input=conllu --outfile='$udfile' $model $tmpfile";
		if ( $verbose ) { print " - Parsing with UDPIPE / $model to $udfile"; };
		if ( $debug ) { print $cmd; };
		if ( $verbose ) {
			`$cmd`;
		} else {
			`$cmd >> /dev/null 2>&1`;
		};
						
	} else {

		print " - Writing CoNLL-U to $udfile";
		# create first, then open for append
		open FILE, ">$udfile";
		close FILE;
		
		open FILE, ">>$udfile";
		binmode (FILE, ":utf8");

		if ( !$model && $lang ) { $model = $lang; };

		$maxpost = 200000; $maxsent = 10000;
		print " - Running UDPIPE from $url / $model";
		if ( length($raw) > $maxpost ) {
			$fcnt = int(length($raw)/$maxpost );
			print " - splitting up in around $fcnt parts of max $maxpost to stay below post limit";
			$partitioned = 1;
		};		
		while ( $raw ne "" ) {
			if ( length($raw) > $maxpost ) {
				# Parse part of the file - starting from the first sentence after $maxpost
				$cutoff = index($raw, "# sent_id", $maxpost);
				$rawpart = substr($raw,0,$cutoff);
				$raw = substr($raw, $cutoff);
				if ( length($rawpart) > $maxpost + $maxsent ) { print "Sentences are too long (".length($rawpart).") - no sentence boundaries?"; print $rawpart; exit; };
				if ( $verbose ) { print " - processing part ".$pcnt++; };
			} else {
				$rawpart = $raw; $raw = "";
			};
		
			%form = (
				"input" => "conllu",
				"tagger" => "$totag",
				"parser" => "$toparse",
				"model" => $model,
				"data" => $rawpart,
			);
	
			if ( !$url ) {
				$url = "http://lindat.mff.cuni.cz/services/udpipe/api/process";
			};
			$res = $ua->post( $url, \%form );
			$jsdat = $res->decoded_content;
			eval {
				$jsonkont = decode_json($res->decoded_content);
			};
			if ( !$jsonkont ) {
				print "UDPipe response error: ";
				print $jsdat;
				if ( $verbose && $jsdat =~ /The payload size is too large/ ) {
					print "Length of \$rawpart: ".length($rawpart);
					print "Lines: ".scalar split("\n", $rawpart);
				};
				exit;
			};
		
			if ( $jsdat =~ /# udpipe_model = ([^ \\]+)/ ) { 
				if ( $modelused ne $1 ) {
					$modelused = $1; 
					print " - Model set by UDPipe to $modelused";
				};
			};

			print FILE $jsonkont->{'result'};
		};
		close FILE;
		
		if ( $debug ) { print `wc $udfile`; };
	
	};
	
};

sub parseconllu($fn) {
	$fn = @_[0]; $tokcnt = 1; %tok = (); %mtok = (); %etok = (); %etok = (); %snts = (); $scnt=1; $mtokcnt=1; $prevdoc = "";
	if ( $fn =~ /\/([a-z]+)_([a-z]+)-ud-([a-z]+).conllu/ ) { $lang = $1; $name = $2; $part = $3; };
	$linex = ""; 

	$/ = "\n";
	if ( $debug ) { print "reading back $fn"; };
	open FILE, $fn; $insent = 0; $inpar = 0; $indoc = 0; $doccnt =1;
	while ( <FILE> ) {	
		$line = $_; chop($line);
		if ( $line =~ /# ?([a-z0-9A-Z\[\]¹_-]+) ?=? (.*)/ ) {
			$snts{$1} = $2;
			if ( $1 eq 'udpipe_model' ) { 
				$usedmodel = $2; 
				if ( $debug ) { print "Model response: $usedmodel"; };
			};
		} elsif ( $line =~ /^(\d+)\t(.*)/ ) {
			$tokcnt++;
			@tmp = split ("\t", $line);
			$tok{$1} = $2; $tokmax = $1; 
			foreach $mfld ( split('\|', $tmp[9]) ) {
				if ( $mfld ne '_' && $mfld !~ /=/ ) {
					$tokid = $mfld;
				};
			};
			$ord2id{$tmp[0]} = $tokid;	
		} elsif ( $line =~ /^(\d+)-(\d+)\t(.*)/ ) {
			# To do : mtok / dtok	
			$mtok{$1} = $3; $etok{$2} = $3; $mtoke{$1} = $2;
		} elsif ( $line =~ /^(\d+\.\d+)\t(.*)/ ) {
			# To do : non-word tokens; ignore for now (extended trees - only becomes relevant if UD integration stronger)
		} elsif ( $line =~ /^#/ ) {
			# To do : ??	
		} elsif ( $line eq '' ) {
			putbacksent(%snts, %tok);
			%tok = (); %mtok = ();  %etok = ();  %ord2id = ();  %snts = ();
		} else {
			print "What? ($line)"; 
		};
	};
	if ( $debug ) { print "done reading back CoNLL-U output ($tokcnt tokens)"; };
	if ( keys %snts ) { $linex .= putbacksent(%snts, %tok); }; # Add the last sentence if needed

	return "";
		
};

sub putbacksent($snt, $tok) {
	( $snt, $tok ) = @_;
	
	if ( !scalar $tok) { return; };
	
	$moresf = "";
	$sid = "s-".$scnt++;
	if ( $mansent ) {
		## Add the sentence into the XML
		$nsnt = XML::LibXML::Element->new("s");
		$nsnt->setAttribute("id", $sid);
	};
	while ( ( $key, $val ) = each (%snt) ) { 
		$att = $key; $att =~ s/\[/_/g; $att =~ s/[^a-z_]//g;
		if ( $att ne 'id' && $att ne '' ) { 
			$moresf .= " $att=\"".textprotect($val)."\""; 
			if ( $nsnt ) {
				$nsnt->setAttribute($att, $val);
			};
		};
	};
	$sentxml = "<s id=\"$sid\" $moresf>"; $dtokxml = "";
	for ( $i=1; $i<=$tokmax; $i++ ) {
		$tokline = textprotect($tok{$i});
		( $word, $lemma, $upos, $xpos, $feats, $head, $deprel, $deps, $misc ) = split("\t", $tokline ); 
		if ( $head ) { $headf = $ord2id{$head}; };
		if ( $mtok{$i} ) { 
			( $mword, $mlemma, $mupos, $mxpos, $mfeats, $mhead, $mdeprel, $mdeps, $mmisc ) = split("\t", $mtok{$i}); 
			if ( $mword =~ / / ) {
				# Multiword
			} else {
				# DToks
				$dtokxml = "<dtok id=\"d-".$ord2id{$i}."\" ord=\"$i\" lemma=\"$mlemma\" upos=\"$mupos\" $xpostag=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" deps=\"$mdeps\" misc=\"$mmisc\" $mheadf>$mword";			
			};
		}		
		if ( $dtokxml ) {
			# Add a dtok (they do not occur, since UDPIPE does not split)
		} else {	
			foreach $mfld ( split('\|', $misc) ) {
				if ( $mfld ne '_' && $mfld !~ /=/ ) {
					$tokid = $mfld;
				} elsif ( $mfld =~ /tok_id=([^|]+)/ ) {
					$tokid = $1;
				};
			};
			$tok = $tokhash{$tokid}; # Read from hash
			if ( $tok ) {
				if ( $nsnt) { 
					if ( $i == 1 ) {
						if ( $debug) { print "inserting ".$nsnt->toString; };
						$tok->parentNode->insertBefore($nsnt, $tok);
						$sameas = "#$tokid";
					} else {
						$sameas = "$sameas #$tokid";
					};
					$nsnt->setAttribute("sameAs", $sameas);
				};
				if ( $i ) { $tok->setAttribute('ord', $i); };
				if ( $lemma && $lemma ne '_' ) { $tok->setAttribute('lemma', $lemma); };
				if ( $upos && $upos ne '_') { $tok->setAttribute('upos', $upos); };
				if ( $xpos && $xpos ne '_') { $tok->setAttribute($xpostag, $xpos); };
				if ( $feats && $feats ne '_') { $tok->setAttribute('feats', $feats); };
				if ( $head && $head ne '_') { $tok->setAttribute('head', $ord2id{$head}); };
				if ( $head && $head ne '_') { $tok->setAttribute('ohead', $head); };
				if ( $deprel && $deprel ne '_') { $tok->setAttribute('deprel', $deprel); };
				if ( $deps && $deps ne '_') { $tok->setAttribute('deps', $deps); };
				if ( $debug ) { print $tokid, $tok->toString; };
			} else {
				print "Token not found: $tokid";
			};
		};
	}; 
	 
	return "";
};

sub textprotect ( $text ) {
	$text = @_[0];
	
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g; 
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&#039;/g;

	return $text;
};

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

