use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;

# Convert a collection of text files into a TEITOK corpus
# By first running UDPIPE over the files, and the converting 
# the CoNLL-U files into TEITOK

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'mixed' => \$mixed, # mixed language corpus - detect for each text
            'model=s' => \$model, # which UDPIPE model to use
            'lang=s' => \$lang, # language of the texts (if no model is provided)
            'orgfolder=s' => \$orgfolder, # Originals folder
            'outfolder=s' => \$outfolder, # Folders where parsed files will be placed
            'tmpfolder=s' => \$tmpfolder, # Folders where conllu files will be placed
            );

$\ = "\n"; $, = "\t";

$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });

if ( !$orgfolder ) { $orgfolder = "Originals"; };
if ( !-d $orgfolder ) { print "No original files folder $orgfolder"; exit; };

if ( !$outfolder ) { $outfolder = "xmlfiles"; };
if ( !$tmpfolder ) { $tmpfolder = "udpipe"; };


( $tmp = $0 ) =~ s/Scripts.*/Resources\/udpipe-models.txt/;
open FILE, $tmp; %udm = ();
while ( <FILE> ) {
	chop;
	( $code, $code3, $lg, $mod ) = split ( "\t" );
	$code2model{$code} = $mod;
	$code2model{$code3} = $mod;
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
	} else {
		$nomodel = 1; $model = "(detect from text)";		
	};
} elsif ( !$models{$model} ) { print "No such UDPIPE model: $model"; exit;  };

print "Using model: $model";

mkdir($tmpfolder);
find({ wanted => \&treatfile, follow => 1, no_chdir => 1 }, $orgfolder);

STDOUT->autoflush();

sub treatfile ( $fn ) {
	$fn = $_;  $orgfile = $fn;
	if ( !-d $fn ) { 
		print "\nTreating $fn";
	
		# read the text
		$/ = undef;
		open FILE, $fn;
		binmode (FILE, ":utf8");
		$raw = <FILE>;
		close FILE;

		if ( $nomodel ) {
			$iso = detectlang($raw);
			if ( !$iso ) { print " - Language detection failed"; next; }
			if ( !$model ) { print " - No model found for $iso / $name"; next; }
			if ( !$mixed ) { $nomodel = 0; };
		};
		
		if ( substr($outfolder,0,1) == "/" ) {
			( $udfile = $fn ) =~ s/.*$orgfolder/$tmpfolder/;
		} else { 
			( $udfile = $fn ) =~ s/$orgfolder/$tmpfolder/;
		};
		$udfile =~ s/\..*?$/\.conllu/;
		( $tmp = $udfile ) =~ s/\/[^\/]+$//;
		`mkdir -p $tmp`;
		$conllu = runudpipe($raw, $model);
		print " - Writing tmp to $udfile";
		open FILE, ">$udfile";
		binmode (FILE, ":utf8");
		print FILE $conllu;
		close FILE;
		
		if ( substr($outfolder,0,1) == "/" ) {
			( $xmlfile = $udfile ) =~ s/.*$orgfolder/$outfolder/;
		} else { 
			( $xmlfile = $fn ) =~ s/$orgfolder/$outfolder/;
		};
		$xmlfile =~ s/\.conllu$/\.xml/;
		( $tmp = $xmlfile ) =~ s/\/[^\/]+$//;
		`mkdir -p $tmp`;
		$teitext = conllu2tei($udfile);
		$now = strftime('%Y-%m-%d', localtime());
		$teixml = "<TEI>
<teiHeader>
	<fileDesc>
		<profileDesc>
			<langUsage><language code=\"$mod2code{$model}\">$mod2lang{$model}</language></langUsage>
		</profileDesc>
	</fileDesc>
	<notesStmt><note n=\"orgfile\">$orgfile</note></notesStmt>
	<revisionDesc><change who=\"udpipe\" when=\"$now\">dependency parsed with the udpipe web-service using model $model</change></revisionDesc>
</teiHeader>
<text>
$teitext
</text>
</TEI>";
		print " - Writing to $xmlfile";
		open FILE, ">$xmlfile";
		# binmode (FILE, ":utf8");
		print FILE $teixml;
		close FILE;
		

	};
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

sub runudpipe ( $raw, $model ) {
	($raw, $model) = @_;

	%form = (
		"tokenizer" => "1",
		"tagger" => "1",
		"parser" => "1",
		"model" => $model,
		"data" => $raw
	);
	
	$url = "http://lindat.mff.cuni.cz/services/udpipe/api/process";
		print " - Running UDPIPE from $url/$model";
	$res = $ua->post( $url, \%form );
	$jsdat = $res->decoded_content;
	$jsonkont = decode_json($jsdat);


	return $jsonkont->{'result'};
	
};

sub conllu2tei($fn) {
	$fn = @_[0]; $tokcnt = 1; %tok = (); %mtok = (); %etok = (); %etok = (); %sent = (); $scnt=1; $mtokcnt=1; $prevdoc = "";
	if ( $fn =~ /\/([a-z]+)_([a-z]+)-ud-([a-z]+).conllu/ ) { $lang = $1; $name = $2; $part = $3; };
	$linex = ""; 

	$/ = "\n";
	open FILE, $fn; $insent = 0; $inpar = 0; $indoc = 0; $doccnt =1;
	while ( <FILE> ) {	
		$line = $_; chop($line);
		if ( $line =~ /# newdoc id = (.*)/ || $line =~ /# newdoc/ ) {
			if ( $inpar ) { $linex .= "</p>\n"; $inpar = 0; }; # A new document always closes the paragraph
			if ( $indoc ) { $linex .= "</doc>\n"; $indoc = 0; }; # A new document always closes the paragraph
			$linex .= "<doc>\n"; 
			$indoc = $1 or $indoc = "doc$doccnt";
			$doccnt++;
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
	if ( $indoc ) { $linex .= "</doc>\n"; };

	return $linex;
		
};

sub makesent($sent, $tok) {
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
		if ( $head ) { $headf = "head=\"w-".$tokid{$head}."\""; };
		if ( $mtok{$i} ) { 
			( $mword, $mlemma, $mupos, $mxpos, $mfeats, $mhead, $mdeprel, $mdeps, $mmisc ) = split("\t", $mtok{$i}); 
			if ( $mword =~ / / ) {
				$sentxml .= "<mtok id=\"w-".$mtok++."\" form=\"$mword\" lemma=\"$mlemma\" upos=\"$mupos\" xpos=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" oid=\"$i\" ohd=\"$head\" deps=\"$deps\" misc=\"$misc\" $mheadf>";			
			} else {
				$dtokxml = "<tok id=\"w-".$tokid{$i}."\" lemma=\"$mlemma\" upos=\"$mupos\" xpos=\"$mxpos\" feats=\"$mfeats\" deprel=\"$mdeprel\" deps=\"$mdeps\" misc=\"$mmisc\" $mheadf>$mword";			
			};
		}		
		if ( $dtokxml ) {
			$dtokxml .= "<dtok id=\"w-".$tokid{$i}."\" lemma=\"$lemma\" upos=\"$upos\" xpos=\"$xpos\" feats=\"$feats\" deprel=\"$deprel\" $headf form=\"$word\"/>";			
		} else {
			$tokxml = "<tok id=\"w-".$tokid{$i}."\" lemma=\"$lemma\" upos=\"$upos\" xpos=\"$xpos\" feats=\"$feats\" deprel=\"$deprel\" $headf>$word</tok>";
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
