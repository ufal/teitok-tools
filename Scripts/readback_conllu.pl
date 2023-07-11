use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;

# Convert a UDPIPE corpus into a TEITOK corpus (to have it convert back to Manatee)

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # verbose mode
            'cid=s' => \$cid, # which UDPIPE model to use
            'input=s' => \$input, # which UDPIPE model to use
            'tmpfolder=s' => \$tmpfolder, # Folders where conllu files will be placed
            );

$\ = "\n"; $, = "\t";

$verbose = 1;

@udflds = ( "ord", "word", "lemma", "upos", "xpos", "feats", "ohead", "deprel", "deps", "misc" ); 
%ord2id = ();

if ( $verbose ) { print "Loading $input into $cid"; };

if ( !-e $cid ) {
	print "No such XML file: $cid";
};
$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $cid );
};
if ( !$doc ) { print "Failed to load XML in $cid"; exit; };
for $tok ( $doc->findnodes("//tok[not(dtok)] | //dtok") ) {
	$id = $tok->getAttribute("id");
	$toklist{$id} = $tok;
};

if ( !-e $input ) {
	print "No such input file: $input";
};
conllu2tei($input);

if ( $test ) { 
print $doc->toString;
} else {

	# Make a backup of the file
	( $buname = $cid ) =~ s/xmlfiles.*\//backups\//;
	$date = strftime "%Y%m%d", localtime; 
	$buname =~ s/\.xml/-$date.nt.xml/;
	$cmd = "/bin/cp $filename $buname";
	`$cmd`;

	open FILE, ">$cid";
	print FILE $doc->toString;
	close FILE;

	print "New data have been added to $cid";
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
			$indoc = $1 or $indoc = "doc$doccnt";
			$doccnt++;
		} elsif ( $line =~ /# newpar id = (.*)/ || $line =~ /# newpar/ ) {
			$inpar = 1;
		} elsif ( $line =~ /# ?([a-z0-9A-Z\[\]¹_-]+) ?=? (.*)/ ) {
			$sent{$1} = $2;
		} elsif ( $line =~ /^(\d+)\t(.*)/ ) {
			placetok($line);
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
			$linex .= makeheads();
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

sub placetok ($tokline) {
	# Place all attributes from the CoNLL-U token on the TEITOK token
	$tokline = @_[0];
	@flds = split("\t", $tokline ); 
	if ( $flds[9] =~ /tokId=([^|]+)/i ) { $tokid = $1; };
	if ( !$tokid ) { 
		print "Oops - no tokid provided: $tokline";
		return -1;
	};
	$ord2id{$flds[0]} = $tokid;
	if ( $flds[6] ne "_" ) {
		$ord2head{$flds[0]} = $flds[6];
	};
	$tok = $toklist{$tokid};
	if ( !$tok ) { 
		print "Oops - no such tok: $tokid";
		return -1;
	};
	for ( $i=0; $i<scalar @udflds; $i++ ) {
		$key = $udflds[$i]; 
		$val = $flds[$i];
		$oval = $tok->getAttribute($key);
		if ( $key eq "word" ) { next; };
		if ( $val eq "_" ) { next; };
		if ( $oval && !$force ) { next; };
		$tok->setAttribute($key, $val);
	};
};

sub makeheads() {
	# Concert ordinal heads to ID based heads
	while ( ( $ord, $head ) = each ( %ord2head ) ) {
		$tok = $toklist{$ord2id{$ord}};
		if ( !$tok ) { 
			print "Oops - no such tok: $tokid";
			return -1;
		};
		$tok->setAttribute("head", $ord2id{$head});
		print $tok->toString;
	};
};

sub textprotect ( $text ) {
	$text = @_[0];
	
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g; 
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&#039;/g;

	return $text;
};
