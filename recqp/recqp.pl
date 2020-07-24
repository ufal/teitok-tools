use XML::LibXML;
use POSIX qw(strftime);

# A version of the standard TEITOK recqp.pl file that build a CWB corpus from xmlfiles
# But which afterwards also builds a Manatee corpus (to be used in KonText)

$scriptname = $0;
($scriptfolder = $scriptname) =~ s/\/recqp\.pl//;
print $scriptfolder;

# Read the parameter set
my $settings = XML::LibXML->load_xml(
	location => "Resources/settings.xml",
); if ( !$settings ) { print FILE "Not able to parse settings.xml"; exit; };

if ( $settings->findnodes("//cqp/\@corpus") ) {
	$cqpcorpus = $settings->findnodes("//cqp/\@corpus")->item(0)->value."";
} else { print FILE "Cannot find corpus name"; exit; };

if ( $settings->findnodes("//cqp/defaults/\@registry") ) {
	$regfolder = $settings->findnodes("//cqp/defaults/\@registry")->item(0)->value."";
} else { $regfolder = "cqp"; };

open FILE, ">tmp/recqp.pid";$\ = "\n";

$starttime = time(); 
print FILE 'Regeneration started on '.localtime();
print FILE 'Process id: '.$$;
print FILE "CQP Corpus: $cqpcorpus";
print FILE 'Removing the old files';
print FILE 'command:
/bin/rm -f cqp/*';
`/bin/rm -f cqp/*`;

print FILE '----------------------';
print FILE '(1) Encoding the corpus';
print FILE "command:
/usr/local/bin/tt-cwb-encode -r $regfolder";
`/usr/local/bin/tt-cwb-encode -r $regfolder`;

print FILE '----------------------';
print FILE '(2) Creating the corpus';
print FILE "command:
/usr/local/bin/cwb-makeall  -r $regfolder $cqpcorpus";
`/usr/local/bin/cwb-makeall  -r $regfolder $cqpcorpus`;

# Now also make the Manatee files and the Kontext corpus
print FILE '----------------------';
print FILE '(3) Creating the manatee/kontext corpus';
$cmd = "/usr/bin/perl $scriptfolder/makemanatee.pl";
print FILE "command:
$cmd";
`$cmd`;

print FILE '----------------------';
$endtime = time();
print FILE 'Regeneration completed on '.localtime();
`mv tmp/recqp.pid tmp/recqp.log`;
close FILE;

$starttxt = strftime("%Y-%m-%d", localtime($starttime));
$timelapse = $endtime - $starttime;
$tmp = `wc -c cqp/word.corpus`;
$size = $tmp/4; $, = "\t";
open FILE, ">tmp/lastupdate.log";
print FILE $starttxt, $timelapse, $size;
close FILE;

