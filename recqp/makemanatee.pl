# Build a Kontext corpus from a CWB corpus (under TEITOK)
# corpus data need to be put in manually into /opt/kontext/{installation}/conf/corplist.xml

use XML::LibXML;
use Cwd;

$scriptname = $0;
( $pwd = $scriptname ) =~ s/\/[^\/]+$//;;

# Read the parameter set
if ( -e "Resources/settings.xml" ) {
	$settings = XML::LibXML->load_xml(
		location => "Resources/settings.xml",
	); if ( !$settings ) { print "Not able to parse settings.xml"; };
} else {
	print "No settings.xml found"; 
};

# Read the shared settings
$scriptname = $0;
( $sharedfolder = $scriptname ) =~ s/\/Scripts\/[^\/]+$//;
if ( $sharedfolder ne '' && -e "$sharedfolder/Resources/settings.xml" ) {
	$sharedsettings = XML::LibXML->load_xml(
		location => "$sharedfolder/Resources/settings.xml",
	); if ( !$sharedsettings ) { print "Not able to parse settings.xml"; };
};

$thispath = getcwd;
($thisfolder = $thispath ) =~ s/.*\///;

$cqpcorpus = $settings->findnodes("//cqp/\@corpus")->item(0)->value; 
$mancorpus = lc($cqpcorpus); $mancorpus =~ s/-/_/g;
$corpusname = $settings->findnodes("//defaults/title/\@display")->item(0)->value;

eval { $baseurl = $settings->findnodes("//defaults/base/\@url")->item(0)->value; };
if ( !$baseurl && $sharedsettings ) {
	$baseurl = $sharedsettings->findnodes("//defaults/base/\@url")->item(0)->value;
	$baseurl =~ s/\{%corpusfolder\}/$thisfolder/;
};
if ( !$baseurl ) { print "Failed to establish base URL"; exit; };

if ( -e "$thispath/manatee/subcorp.def" ) { 
	$subcdef = "SUBCDEF \"$thispath/manatee/subcorp.def\"
SUBCBASE \"$thispath/manatee/subcorp\""; 
}; 

# Build the registry file
$reg = "NAME \"$corpusname\"
PATH  \"$thispath/manatee/corp\"
ENCODING utf-8
VERTICAL \"$thispath/manatee/corpus.vrt\"
$subcdef

ATTRIBUTE word
ATTRIBUTE lc {
        DYNAMIC utf8lowercase
        DYNLIB internal
        FUNTYPE s
        FROMATTR word
        TYPE index
        TRANSQUERY yes
}
ATTRIBUTE id
";

@atts = ('word', 'id');
foreach $node ( $settings->findnodes("//cqp/pattributes/item") ) {
	$att = $node->getAttribute('key');
	$katt = $node->getAttribute('kontext') or $katt = $att; # Allow patts to have a different name in Kontext
	if ( $att eq "word" || $att eq 'id' || $katt eq '--' ) { next; };
	$reg .= "ATTRIBUTE ".lc($katt)."\n";
	push(@atts, $att);
};
$attslist = "-P ".join(" -P ", @atts);

$reg .= "\nDOCSTRUCTURE text\n\nSTRUCTURE crp {\n\tATTRIBUTE server\n\tATTRIBUTE path\n}\n\n";

foreach $section ( $settings->findnodes("//cqp/sattributes/item") ) {
	$seg = $section->getAttribute('key');
	$reg .= "STRUCTURE $seg {\n";
	$attslist .= " -S $seg";
	foreach $node ( $section->findnodes("./item") ) {
		$sub = $node->getAttribute('key');
		$reg .= "	ATTRIBUTE ".lc($sub)."\n";
		$attslist .= " -S ".$seg."_$sub";
	};
	if ( $seg eq 'text' ) {
		$reg .= "	ATTRIBUTE id\n	ATTRIBUTE wordcount\n";
		$attslist .= " -S text_id";
	};
	$reg .= "}\n\n";
};


print "Writing registry to /corpora/registry/$mancorpus\n";
open FILE, ">/corpora/registry/$mancorpus";
binmode(FILE, ":utf8");
print FILE $reg;
close FILE;

if ( !-d "manatee" ) { mkdir("manatee"); };
if ( !-d "manatee/corp" ) { mkdir("manatee/corp"); };

# Export and clean-up the VRT file from CQP
&runcmd("/usr/local/bin/cwb-decode -Cx -r cqp $cqpcorpus $attslist | /usr/bin/perl $pwd/cleanvrt.pl $baseurl > manatee/corpus.vrt");
# Import the VRT into Manatee
&runcmd("/usr/bin/compilecorp --recompile-corpus --no-ske $mancorpus manatee/corpus.vrt");

# Since compilecorp does not seem to properly write the subcorpora, run mksubc here again
if ( -e "$thispath/manatee/subcorp.def" ) {
	`mkdir -p manatee/subcorp`;
	&runcmd("/usr/bin/mksubc $mancorpus manatee/subcorp manatee/subcorp.def");
};

# Restart Kontext
&runcmd("sudo systemctl restart kontext");

# Test whether the last line is not an "Oops"
$last = `tail -n 1 manatee/corpus.vrt`;
if ( $last =~ /Oops/ ) { print "Compilation of Manatee corpus failed: $last"; }; 

print "Writing registry to manatee/$mancorpus\n";
open FILE, ">manatee/$mancorpus";
binmode(FILE, ":utf8");
print FILE $reg;
close FILE;

sub runcmd ( $cmd ) {
	$cmd = @_[0];
	print $cmd."\n";
	print `$cmd`;
};