use Encode qw(decode encode);
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use HTML::Entities;
use XML::LibXML;
use Getopt::Long;
 use Data::Dumper;
use POSIX qw(strftime);

# Convert a Manatee corpus into a TEITOK corpus
# Manatee is a corpus tool used as backend by SketchEngine (noSKE, Kontext)

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'force' => \$force, # write even if project exists
            'corpus=s' => \$corpus, # corpus to be converted
            'regfolder=s' => \$regfolder, # registry folder
            'corpfolder=s' => \$corpfolder, # the name of the folder where to create the TEITOK project
            'textnode=s' => \$textnode, # Node to use in the input to split XML files (default: <doc>)
            'makeproject' => \$makeproject, # whether to make a full TEITOK project
            );

$\ = "\n"; $, = "\t";

if ( !$corpus ) { $corpus = shift; };
if ( !$regfolder ) { $regfolder = "/opt/kontext/data/registry"; };
if ( !$textnode ) { $textnode = "doc"; };
if ( !$corpfolder ) { 
	$corpfolder = $ENV{"HOME"}."/manatee2teitok"; 
	if ( !-d $corpfolder ) { mkdir ($corpfolder); };
};

# Read the Registry file

$/ =  undef;
open FILE, "$regfolder/$corpus";
$reg = <FILE>;
close FILE;

if ( !$reg ) { print "No such registry: $regfolder/$corpus"; exit; };

if ( !$vrt && $reg =~ /VERTICAL "([^"]+)"/ ) { $vrt = $1; };
if ( $reg =~ /NAME "([^"]+)"/ ) { $corpname = $1; }; if ( !$corpname ) { $corpname = $corpus; };
if ( $reg =~ /PATH "([^"]+)"/ ) { $manfolder = $1; };

@flds = ();
while ( $reg =~ /\nATTRIBUTE ([^ \n]+)/g ) { 
	$tmp = $1;
	if ( $tmp ne 'lc' ) {
		push(@flds, $tmp);
	};
};
%sflds = ();
while ( $reg =~ /\nSTRUCTURE ([^ ]+) \{(.+?)\}/smig ) { 
	$lvl = $1; $tmp2 = $2; 
	$sflds{$lvl} = ();
	while ( $tmp2 =~ /\tATTRIBUTE ([^ \n]+)/g ) { 
		$tmp = $1;
		push(@{$sflds{$lvl}}, $tmp);
	};
};

if ( !-f $vrt ) { 
	# If the vrt file does not exist, create it from the Manatee corpus
	`decodevert $corpus > $vrt`;
};

if ( !-f $vrt ) { print "No such VRT file: $vrt"; exit; };

if ( !-d $corpfolder ) {
	print "No such folder: $corpfolder";
}; 
if ( -d "$corpfolder/$corpus" && !$force ) {
	print "Folder $corpfolder/$corpus already exists; please remove"; exit;
};

	mkdir("$corpfolder/$corpus");
	mkdir("$corpfolder/$corpus/xmlfiles");
	mkdir("$corpfolder/$corpus/Resources");

if ( !-d "$corpfolder/$corpus" ) {
	print "Unable to create $corpfolder/$corpus"; exit;
};

if ( $sflds{$textnode} ) { $splitting = 1; };

# Build the settings file
foreach $fld ( @flds ) {
	$patts .= "			<item key=\"$fld\"/>\n";
	if ( $fld eq 'word' || $fld =~ /form$/ ) {
		$forms .= "				<item key=\"$fld\" display=\"$fld\"/>\n";
	} else {
		$tags .= "				<item key=\"$fld\" display=\"$fld\"/>\n";
	};
};
while ( ( $key, $val ) = each ( %sflds) ) {
	if ( $splitting && $key eq 'crp' ) { next; };
	$satts .= "		    <item key=\"$key\" level=\"$key\" display=\"$key\">\n";
	foreach $key2 ( @{$val} ) {
		$satts .= "    			<item key=\"$key2\" display=\"$key2\"/>\n";
	};
	$satts .= "		    </item>\n";
};
open FILE, ">$corpfolder/$corpus/Resources/settings.xml";
$corpid = uc($corpus);
print FILE "<ttsettings>
	<defaults>
		<title display=\"$corpname\"/>
	</defaults>
	<cqp corpus=\"$corpid\" searchfolder=\"xmlfiles\">	
		<pattributes>
$patts		</pattributes>
		<sattributes>
$satts		</sattributes>
	</cqp>

	<xmlfile>
		<pattributes>
			<forms>
$forms			</forms>
			
			<tags>			
$tags			</tags>
		</pattributes>
		<sattributes>
$satts
		</sattributes>
	</xmlfile>
</ttsettings>";
close FILE;

$teiheader = "<teiHeader/>";

if ( $splitting ) {
	print "Creating corpus in $corpfolder/$corpus/ based on $textnode from $vrt";	
} else {
	print "Creating $corpfolder/$corpus/xmlfiles/fromvrt.xml from $vrt";
	open OUTFILE, ">$corpfolder/$corpus/xmlfiles/fromvrt.xml";
	print OUTFILE "<TEI>\n$teiheader\n<text>\n";
};
$/ = "\n"; $\ = undef; $glue = 0; $doccnt = 1;
open FILE, $vrt;
open OUTFILE, *STDOUT;
while ( <FILE> ) {
	chop;
	$line = $_; 
	if ( $splitting && $line =~ /^<\/?crp( |>)/ ) {
		# Ignore the crp node if we are splitting files
	} elsif ( $line =~ /^<$textnode( |>)/ ) {
		if ( $line =~ / id="([^"]+)"/ ) {
			$filename = $1;
		} else { $filename = $textnode.$doccnt++; };
		open OUTFILE, ">$corpfolder/$corpus/xmlfiles/$filename.xml";
		print "Creating $filename.xml\n";
		print OUTFILE "<TEI>\n$teiheader\n";
		if ( $textnode ne 'text' ) { print OUTFILE  "<text>\n"; };
		print OUTFILE $line."\n"; 
	} elsif ( $line =~ /^<\/$textnode( |>)/ ) {
		if ( $textnode ne 'text' ) { print OUTFILE $line; };
		print OUTFILE "\n</text>\n</TEI>";	
		close OUTFILE;
		open OUTFILE, *STDOUT;
	} elsif ( $line =~ /^</ ) {
		print OUTFILE $line;
		if ( $line eq '<g/>' ) { $glue = 1; } elsif ( $line =~ /^<(p|s) / ) { $glue = 0; }; 
		if ( !$glue ) { print OUTFILE "\n"; };
	} else {
		@tmp = split ( "\t", $line ); $atts = "";
		for ( $i=1; $i<scalar @flds; $i++ ) {
			$atts .= " ".$flds[$i]."=\"".$tmp[$i]."\"";
		};
		$tok = "<tok $atts>$tmp[0]</tok>";
		if ( !$glue ) { print OUTFILE " "; }; $glue = 0; # Print a space unless after <g/>
		print OUTFILE $tok;
	};
	
};
close FILE;
if ( !$splitting ) {
	print OUTFILE "\n</text>\n</TEI>";
};
close OUTFILE;

