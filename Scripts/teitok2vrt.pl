use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Convert a TEITOK/XML file to the VRT format
# VRT (https://www.kielipankki.fi/support/vrt-format/) is an annotation format used for instance by CWB

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # vebose mode
            'help' => \$help, # help
            'headed' => \$headed, # print header line?
            'file=s' => \$filename, # input file name
            'settings=s' => \$setfile, # input file name
            'fields=s' => \$fields, # Fields to export
            'output=s' => \$output, # output file name
            'outfolder=s' => \$outfolder, # Originals folder
            );

$\ = "\n"; $, = "\t";

$parser = XML::LibXML->new(); 

if ( !$filename ) { $filename = shift; };
if ( $debug ) { $verbose = 1; };

if ( $help ) {
	print "Usage: perl teitok2conllu.pl [options] filename

Options:
	--verbose	verbose output
	--debug		debugging mode
	--file		filename to convert
	--output	conllu file to write to
	--fields=s		XML attribute to use for @xpos
	--form=s	TEITOK inherited form to use as @form
	";
	exit;

};

if ( !$fields ) { $fields = "id,form"; };
@flds = split(",", $fields);

# We need an inheritance from the settings
$doc = "";
if ( !$setfile ) { $setfile = "Resources/settings.xml"; };
eval {
	$setxml = $parser->load_xml(location => $setfile);
};
if ( $setxml ) { 
	if ( $verbose ) { print "Reading settings from $setfile for inheritance from $wform	"; };
	foreach $node ( $setxml->findnodes("//xmlfile/pattributes/forms/item") ) {
		$from = $node->getAttribute("key");
		$to = $node->getAttribute("inherit");
		$inherit{$from} = $to;
		$forms{$from} = 1;
	};
} else {
	@tmp = split(",", $wform);
	foreach $to ( @tmp ) {
		if ( $from ) { $inherit{$from} = $to; };
		$from = $to;
	};
};
if ( !$inherit{'form'} ) { $inherit{'form'} = "pform"; };
if ( $debug ) { while ( ( $key, $val ) = each ( %inherit ) ) { print "Inherit: $key => $val"; }; };

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

if ( !$output && $outfolder ) { 
	( $output = $filename ) =~ s/\.xml/.conllu/; 
	if ( $outfolder ) { 
		$output =~ s/.*\//$outfolder\//;
	};
} else {
	( $ofldr = $output ) =~ s/[^\/]+$//;
	if ( $oflder ) {
		if ( $debug ) { print "Creating $ofldr when needed"; };
		`mkdir -p $ofldr`;
	};
};

if ( !$doc->findnodes("//tok") ) {
	print "Error: cannot convert untokenized files to VRT";
	exit;
};

if ( $output ) {
	print "Writing converted file to $output\n";
	open OUTFILE, ">$output";
} else {
	*OUTFILE = STDOUT;
};
binmode(OUTFILE, ":utf8");



# Convert <dtok> to <tok> (to be dealt with later)
$scnt = 1;

$docid = $filename; $docid =~ s/.*\///; $docid =~ s/\.xml//;

if ( $headed  ) {
	print OUTFILE join("\t", @flds);
};

foreach $tok ( $doc->findnodes("//tok") ) {
	@line = ();
	foreach $fld ( @flds ) {
		if ( $forms{$fld} ) {
			$val = calcform($tok, $fld);
		} else {
			$val = getAttVal($tok, $fld);
		};
		push ( @line, $val );
	};
	if ( $splitsent ) { print OUTFILE join("\t", @line); };
	if ( $line[1] =~ /^[.!?]$/ ) { 
		print OUTFILE "";
	};
	$num++;
};
close OUTFLE;

sub getAttVal ($node, $att ) {
	( $node, $att ) = @_;
	$val = $node->getAttribute($att);
	$val =~ s/^\s+|\s+$//g;
	$val =~ s/\t| //g;
	$val =~ s/ +/ /g;
	
	if ( !$val ) { $val = "_"; };
	
	return $val;
};

sub calcform ( $node, $form ) {
	( $node, $form ) = @_;
	if ( !$node ) { return; };
	
	if ( $form eq 'pform' ) {
		$value = $node->toString;
		$value =~ s/<[^>]*>//g;
		return $value;
		# return $node->textContent;
	} elsif ( $node->getAttribute($form) ) {
		return $node->getAttribute($form);
	} elsif ( $inherit{$form} ) {
		return calcform($node, $inherit{$form});
	} else {
		return "_";
	};
};