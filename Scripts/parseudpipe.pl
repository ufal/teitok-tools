use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Parse a tokenized corpus using UDPIPE

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'writeback' => \$writeback, # write back to original file or put in new file
            'file=s' => \$file, # which UDPIPE model to use
            'model=s' => \$model, # which UDPIPE model to use
            'lang=s' => \$lang, # language of the texts (if no model is provided)
            'folder=s' => \$folder, # Originals folder
            'token=s' => \$token, # token node
            'tokxp=s' => \$tokxp, # token XPath
            'sent=s' => \$sent, # sentence node
            'sentxp=s' => \$sentxp, # sentence XPath
            'atts=s' => \$atts, # attributes to use for the word form
            'forms=s' => \$atts, # attribute for the normalized form
            );

$\ = "\n"; $, = "\t";

$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
$parser = XML::LibXML->new(); 

if ( !$token ) { $token = "tok"; };
if ( !$atts ) { $atts = "nform,reg,fform,expan,form"; };

if ( !$file ) { $file = shift; };

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
		print "Choosing $model for $lang";
	};
} elsif ( !$models{$model} ) { print "No such UDPIPE model: $model"; exit;  };

print "Using model: $model";

if ( !$writeback) { mkdir("udpipe"); };
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
		print "\nTreating $fn";
	
		# read the XML
		eval {
			$xml = $parser->load_xml(location => $fn, load_ext_dtd => 0);
		};
		if ( !$xml ) { 
			print "Invalid XML in $fn";
			continue;
		};
		if ( !$tokxp ) { $tokxp = "//$token"; };
		$num = 1; 
		if ( $sent || $sentxp ) { 
			$sntcnt = 1;
			if ( !$sentxp ) { $sentxp = "//$sent"; };
			foreach $snt ( $xml->findnodes($sentxp) ) {
				$sentid = $snt->getAttribute('id');
				if ( !$sentid ) { $sentid = "s-".$sntcnt++; $snt->setAttribute('id', $sentid); };
				$toklist .= "# sent_id $sentid\n";
				foreach $tok ( $snt->findnodes(".//$token") ) {
					$tokxml = parsetok($tok);
					$toklist .= $tokxml;
					@tmp = split("\t", $tokxml); 
					$rawtxt .= $tmp[1]." ";
					$num++;
				};
				$toklist .= "\n"; $num = 1;
			};
		} else {
			$snum = 1;
			$toklist = "# sent_id s-".$snum++."\n";
			foreach $tok ( $xml->findnodes($tokxp) ) {
				if ( $newsent ) { $toklist .= "# sent_id s-".$snum++."\n"; };
				$newsent = 0;
				$tokxml = parsetok($tok); 
				$toklist .= $tokxml;
				@tmp = split("\t", $tokxml); 
				$rawtxt .= $tmp[1]." ";
				if ( $tmp[1] =~ /^[.!?]$/ ) { 
					$toklist .= "\n"; 
					$newsent = 1;
					$num = 0;
				};
				$num++;
			};
		};
		utf8::upgrade($toklist);
	
		if ( !$model ) {
			$lang = detectlang($rawtxt);
			$model = $code2model{$lang};
			print "Detected language : $lang => $model";
			if ( !$model ) { print "No UDPIPE models for $lang"; exit; };
		};
	
		if ( $debug ) { 
			binmode(STDOUT, ":utf8");
			print $toklist; 
		};
				
		$udfile = $fn;
		if ( $folder eq '' ) { $udfile = "udpipe/$udfile"; };
		$udfile =~ s/\..*?$/\.conllu/;
		( $tmp = $udfile ) =~ s/\/[^\/]+$//;
		`mkdir -p $tmp`;
		$conllu = runudpipe($toklist, $model, $udfile);
		
		parseconllu($udfile);		
		
		# Add the revision statement
		$revnode = makenode($xml, "/TEI/teiHeader/revisionDesc/change[\@who=\"xmltokenize\"]");
		$when = strftime "%Y-%m-%d", localtime;
		$revnode->setAttribute("when", $when);
		$revnode->appendText("parsed with UDPIPE using $model");
		
		if ( $writeback ) { 
			$outfile = $orgfile;
		} else {
			( $outfile = $udfile ) =~ s/udpipe/parsed/;
			$outfile =~ s/\.conllu$/\.xml/;
			( $tmp = $outfile ) =~ s/\/[^\/]+$//;
			`mkdir -p $tmp`;
		};
		print "Writing parsed file to $outfile\n";
		open OUTFILE, ">$outfile";
		print OUTFILE $xml->toString;	
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
	if ( !$form ) { $form = "_"; };	
	return "$num\t$form\t_\t_\t_\t_\t_\t_\t_\t$tokid\n"; $num++;
};

sub detectlang ( $text ) {
	$text = @_[0];
	%form = (
		"data" => $text
	);
	
	$url = 'http://quest.ms.mff.cuni.cz/teitok-dev/teitok/cwali/index.php?action=cwali';
	$res = $ua->post( $url, \%form );
	$jsdat = $res->decoded_content;
	$jsonkont = decode_json($jsdat);
	$iso = $jsonkont->{'best'}; $name = $jsonkont->{'name'};
	$model = $code2model{$iso} or $model = $lang2model{$name}; 
	print " - Language detected: $iso / $name, using $model";
	
	return $iso;
};

sub runudpipe ( $raw, $model, $udfile ) {
	($raw, $model) = @_;

	if ( -e "/usr/local/bin/udpipe" ) {
		
		( $modelroot = $scriptname ) =~ s/\/[^\/]+$//;
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
		
		print " - Writing VRT file to $tmpfile";
		$cmd = "/usr/local/bin/udpipe --tag --parse --input=conllu --outfile='$udfile' $modelfile $tmpfile";
		print " - Parsing with UDPIPE / $model to $udfile";
		print $cmd;
		`$cmd`;
						
	} else {

		%form = (
			"input" => "conllu",
			"tagger" => "1",
			"parser" => "1",
			"model" => $model,
			"data" => $raw,
		);
	
		$url = "http://lindat.mff.cuni.cz/services/udpipe/api/process";
			print " - Running UDPIPE from $url / $model";
		$res = $ua->post( $url, \%form );
		$jsdat = $res->decoded_content;
		# $jsonkont = decode_json(encode("UTF-8", $res->decoded_content));
		$jsonkont = decode_json($res->decoded_content);

		print " - Writing CoNLL-U to $udfile";
		open FILE, ">$udfile";
		binmode (FILE, ":utf8");
		print FILE $jsonkont->{'result'};
		close FILE;
	
	};
	
};

sub parseconllu($fn) {
	$fn = @_[0]; $tokcnt = 1; %tok = (); %mtok = (); %etok = (); %etok = (); %sent = (); $scnt=1; $mtokcnt=1; $prevdoc = "";
	if ( $fn =~ /\/([a-z]+)_([a-z]+)-ud-([a-z]+).conllu/ ) { $lang = $1; $name = $2; $part = $3; };
	$linex = ""; 

	$/ = "\n";
	open FILE, $fn; $insent = 0; $inpar = 0; $indoc = 0; $doccnt =1;
	while ( <FILE> ) {	
		$line = $_; chop($line);
		if ( $line =~ /# ?([a-z0-9A-Z\[\]¹_-]+) ?=? (.*)/ ) {
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
			putbacksent(%sent, %tok);
			%tok = (); %mtok = ();  %etok = ();  %tokid = ();  %sent = ();
		} else {
			print "What? ($line)"; 
		};
	};
	if ( keys %sent ) { $linex .= putbacksent(%sent, %tok); }; # Add the last sentence if needed

	return "";
		
};

sub putbacksent($sent, $tok) {
	( $sent, $tok ) = @_;
	
	if ( !scalar $tok) { return; };
	
	$moresf = "";
	while ( ( $key, $val ) = each (%sent) ) { 
		$att = $key; $att =~ s/\[/_/g; $att =~ s/[^a-z_]//g;
		if ( $att ne 'id' && $att ne '' ) { $moresf .= " $att=\"".textprotect($val)."\""; };
	};
	$sentxml = "<s id=\"s-".$scnt++."\" $moresf>"; $dtokxml = "";
	for ( $i=1; $i<=$tokmax; $i++ ) {
		$tokline = textprotect($tok{$i});
		( $word, $lemma, $upos, $xpos, $feats, $head, $deprel, $deps, $misc ) = split("\t", $tokline ); 
		if ( $head ) { $headf = $tokid{$head}; };
		if ( $mtok{$i} ) { 
			( $mword, $mlemma, $mupos, $mxpos, $mfeats, $mhead, $mdeprel, $mdeps, $mmisc ) = split("\t", $mtok{$i}); 
			if ( $mword =~ / / ) {
				# Multiword
			} else {
				# DToks
				$dtokxml = "<tok id=\"w-".$tokid{$i}."\" lemma=\"$mlemma\" upos=\"$mupos\" xpos=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" deps=\"$mdeps\" misc=\"$mmisc\" $mheadf>$mword";			
			};
		}		
		if ( $dtokxml ) {
			# Add a dtok
		} else {	
			$tokid = $misc; 
			$tmp = "//".$token."[\@id=\"$tokid\"]";
			$tok = $xml->findnodes($tmp)->item(0);
			if ( $lemma ) { $tok->setAttribute('lemma', $lemma); };
			if ( $upos ) { $tok->setAttribute('upos', $upos); };
			if ( $xpos ) { $tok->setAttribute('xpos', $xpos); };
			if ( $feats ) { $tok->setAttribute('feats', $feats); };
			if ( $head ) { $tok->setAttribute('head', $tokid{$head}); };
			if ( $deprel ) { $tok->setAttribute('deprel', $deprel); };
			if ( $deps ) { $tok->setAttribute('deps', $deps); };
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

