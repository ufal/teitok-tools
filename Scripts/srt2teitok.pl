use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Convert an SRT file to TEITOK/XML
# SRT (https://en.wikipedia.org/wiki/SubRip) is a format for audio transcription used in subtitles

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # which UDPIPE model to use
            'audio=s' => \$audiofile, # filename of the corresponding audio
            'ext=s' => \$ext, # extention of the corresponding audio
            'output=s' => \$output, # which UDPIPE model to use
            'morerev=s' => \$morerev, # language of input
            'split' => \$split, # Split into 1 file per language
            );

$\ = "\n"; $, = "\t";
if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;

binmode(STDOUT, ":utf8");

open FILE, $filename;
binmode(FILE, ":utf8");
$/ = undef;
$content = <FILE>;
close FILE;

@lines = split("\n", $content);

if ( !$ext ) {
	if ( $audiofile ) {
	( $ext = $audiofile ) =~ s/.*\.//;		
	} else { $ext = "wav"; }
};
if ( !$audiofile ) {
	( $audiofile = $filename ) =~ s/\.srt/.$ext/;
	$audiofile =~ s/.*\///;
};

$tei = "<TEI>\n<teiHeader>
<recordingStmt>
	<recording type=\"audio\">
 		<media mimeType=\"audio/$ext\" url=\"Audio/$audiofile\">
		<desc/> 
		</media>
	</recording>

</recordingStmt>
<revisionDesc>
	$morerev<change who=\"srt2teitok\" when=\"$today\">Converted from SRT file $filename</change>
</revisionDesc>
</teiHeader>\n<text>";

for ( $i=0; $i<scalar @lines; $i = $i+4 ) {
	$n = $lines[$i];
	if ( $lines[$i+1] =~ /(.+) --> (.+)/ ) {
		$start = time2secs($1);
		$end = time2secs($2);
	};
	$text = xmlprotect($lines[$i+2]);
	
	$tei .= "<u n=\"$n\" id=\"u-$n\" start=\"$start\" end=\"$end\">$text</u>\n";
};
$tei .= "</text>\n</TEI>";

if ( !$output ) {
	( $output = $filename ) =~ s/\.srt/.xml/;
};
open OUTFILE, ">$output";
binmode(OUTFILE, ":utf8");
print OUTFILE $tei;
close OUTFLE;

print "TEITOK/XML saved to $output";

sub time2secs($time) {
	$time = @_[0];
	
	if ( $time =~ /(\d\d):(\d\d):(\d\d),(\d\d\d)/ ) {
		$secs = int($1)*60*60 + int($2)*60 + int($3) + int($4)/1000;
		return $secs;
	};
	
	return 0;
};

sub xmlprotect($string) {
	$string = @_[0];
	
	$string =~ s/\&/&amp;/g;
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;
	
	return $string;
	
}