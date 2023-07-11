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
            'test' => \$test, # test mode (print, do not save)
            'nobu' => \$nobu, # do not make a backup
            'emptys' => \$emptys, # do not make a backup
            'cid=s' => \$cid, # which UDPIPE model to use
            'input=s' => \$input, # which UDPIPE model to use
            'tmpfolder=s' => \$tmpfolder, # Folders where conllu files will be placed
            );

$\ = "\n"; $, = "\t";

@udflds = ( "ord", "word", "lemma", "upos", "xpos", "feats", "ohead", "deprel", "deps", "misc" ); 
%ord2id = ();
@nerlist = ();

@warnings = ();

if ( $debug ) { $verbose = 1; };
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
$/ = undef;
open FILE, $input;
$jstr = <FILE>;
close FILE;
$json = decode_json($jstr);

# Place the NER if we have any
for $ner ( @{$json->{name}} ) {
	$sameas = $ner->{sameAs};
	$ener = $doc->findnodes("//name[\@sameAs=\"$sameas\"]");
	if ( $ener ) {
		$ener->setAttribute('type', $ner->{type});
	} else {
		@tmp = split(' ', $sameas);
		$tok1 = substr($tmp[0], 1);
		$tok = $toklist{$tok1};
		
		$newner = $doc->createElement("name");
		foreach $key ( keys(%{$ner}) ) {
			$newner->setAttribute($key, $ner->{$key});
		};
		$tok->parentNode->insertBefore($newner, $tok);
		if ( !$emptys ) {
			moveinside($newner);
		};
	};
};

if ( scalar @warnings ) {
	$warnlist = "'warnings': ['".join("', '", @warnings)."']";
};	

if ( $test ) { 
	print $doc->toString;
} else {

	# Make a backup of the file
	if ( !$nobu ) {
		( $buname = $cid ) =~ s/xmlfiles.*\//backups\//;
		$date = strftime "%Y%m%d", localtime; 
		$buname =~ s/\.xml/-$date.nt.xml/;
		$cmd = "/bin/cp '$filename' '$buname'";
		`$cmd`;
	};
	
	open FILE, ">$cid";
	print FILE $doc->toString;
	close FILE;

	print "{'success': 'CoNLL-U file successfully read back to $cid'$warnlist}";

};


sub moveinside ( $node ) {
	# Move the @sameAs tokens inside
	$node = @_[0];
	$sameas = $node->getAttribute('sameAs');
	$sameas =~ s/#//g;
	@list = split(' ', $sameas);
	$tok1 = $list[0]; $tok2 = $list[-1];
	if ( !$tok1 || !$tok2 || !$toklist{$tok1} || !$toklist{$tok2} ) { push(@warning, "unable to move tokens inside NER"); return -1; };
	if ( $toklist{$list[0]}->parentNode == $toklist{$list[-1]}->parentNode ) {
		$curr = $node;
		while ( $curr->getAttribute("id") ne $list[-1] ) {
			$curr = $curr->nextSibling();
			if ( !$curr ) { push(@warning, "unable to move tokens inside NER"); return -1; };
			$node->addChild($curr);
		};
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
