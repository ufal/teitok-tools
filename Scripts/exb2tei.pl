use Getopt::Long;

# Script to convert an EXMARaLDA file into TEITOK/XML
# EXB (https://standards.clarin.eu/sis/views/view-format.xq?id=fEXB) is a audio format from EXMARaLDA

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'file=s' => \$filename, # language of input
            'morerev=s' => \$morerev, # language of input
            'outfolder=s' => \$outfolder, # language of input
            );

$/ = undef; $\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

open FILE, $filename;
binmode (FILE, ":utf8");
$xml = <FILE>;
close FILE;

binmode (STDOUT, ":utf8");

if ( $filename =~ /([^\/.]+)\.exb/ ) { $fid = $1; } else { print " -- incorrect filename: $filename"; exit; };
if ( $filename =~ /Originals\/([^\/.]+)/ ) { $folder = $1; };


while ( $xml =~ /<speaker id="([^"]+)">\s*<abbreviation>([^>]+)<\/abbreviation>/gsmi ) {
	$spid{$1} = $2;
};
$spcnt = scalar keys %spid;

while ( $xml =~ /<tli id="([^"]+)" time="([^"]+)"[^>]*\/>/gsmi ) {
	$tli{$1} = $2;
};


%s = ();
while ( $xml =~ /<tier id="([^"]+)" speaker="([^"]+)"[^>]*>(.*?)<\/tier>/gsmi ) {
	$speaker = $2; 
	$tier = $1;
	$eventlist = $3;
	$speakerid = $spid{$speaker} or $speakerid = $speaker;
	
	while ( $eventlist =~ /<event start="([^"]+)" end="([^"]+)">(.*?)<\/event>/gsmi ) {
		$sli = $1;
		$start = $tli{$sli}; 
		$eli = $2;
		$end = $tli{$eli}; 
		$text = $3; 
		
		if ( $debug ) { print "BA | $text"; };

		$text =~ s/<!\[CDATA\[(.*?)\]\]>/\1/g;
		
		# Protect difficult symbols
		$text =~ s/</«/g;
		$text =~ s/>/»/g;

		if ( $debug ) { print "S1 | $text"; };
		
		# word [//] or <word word> [//] indicate a correction by the speaker
		$text =~ s/([^<>]*) \[\/\/\/\]/<del reason="reformulation">\1<\/del>/g;
		
		# word [//] or <word word> [//] indicate a correction by the speaker
		$text =~ s/«([^<>»]+)» \[\/\/\]/<del reason="reformulation">\1<\/del>/g;
		$text =~ s/([^ <>»]+) \[\/\/\]/<del reason="reformulation">\1<\/del>/g;

		if ( $debug ) { print "Sa | $text"; };

		
		# word [//] or <word word> [//] indicate a correction by the speaker
		$text =~ s/«([^<>»]+)» \[\/\]/<del reason="repetition">\1<\/del>/g;
		$text =~ s/([^<> »]+) \[\/\]/<del reason="repetition">\1<\/del>/g;

		if ( $debug ) { print "S2 | $text"; };

		$text =~ s/xxx/<gap reason="unintelligible"\/>/g;
		$text =~ s/yyyy/<gap extend="2+" reason="unintelligible"\/>/g;

		# Non-tokens - hhh or &xxx
		$text =~ s/hhh/<vocal><desc>hhh<\/desc><\/vocal>/g;
		$text =~ s/&(ah|uh|hum|eh)/<vocal><desc>\1<\/desc><\/vocal>/g;

		$text =~ s/&([^ <>;\/]+)([^;])/<del reason="truncated">\1<\/del>\2/g;

		if ( $debug ) { print "S3 | $text"; };
		
		# $text =~ s/&(?![a-z0-9#]+;)/&amp;/g; # This should not be necessary

		$text =~ s/ > / <cont\/> /g;
		$text =~ s/ >$/ <cont\/>/g;

		$text =~ s/ \/ / <pause type="short"\/> /g;
		$text =~ s/ \/\/ / <pause type="long"\/> /g;
		$text =~ s/ \/\/$/ <pause type="long"\/>/g;

		$text =~ s/ \+ / <shift\/> /g;
		$text =~ s/ \+$/ <shift\/>/g;
		
		# Now (un)protect special symbols;
		$text =~ s/&/&amp;/g;
		$text =~ s/«/&lt;/g;
		$text =~ s/»/&gt;/g;
		
	
		if ( $spcnt > 1 ) {
			$uwho = " who=\"$speakerid\"";
		};

		if ( $debug ) { print "AA | $text"; };

		$text =~ s/^\s+//; $text =~ s/\s+$//; # Removing trailing/starting spaces

		if ( $text ne '' ) {
			$s{$start} .= "\n<u start=\"$start\" end=\"$end\"$uwho>$text</u>";
		};
	};
};

@s = sort @s;

if ( $spcnt == 1 ) {
	@tmp = values %spid;
	$spid1 = $tmp[0];
	$twho = " who=\"$spid1\"";
};

# Now do the header
if ( $xml =~ /<meta-information.*?<\/meta-information>/gsmi ) {
	$metadata = $&; # print $metadata;
	
	if ( $metadata =~ /<transcription-name>(.*?)<\/transcription-name>/ ) { $meta{'title'} = $1; } else { $title = $fid; };
	if ( $metadata =~ /<comment>(.*?)<\/comment>/ ) { $meta{'comment'} = $1; };
	if ( $metadata =~ /<project-name>(.*?)<\/project-name>/ ) { $meta{'project'} = $1; };
	if ( $metadata =~ /<ud-information attribute-name="Topic">(.*?)<\/ud-information>/ ) { $meta{'topic'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Country">(.*?)<\/ud-information>/ ) { $meta{'country'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Place of the recording">(.*?)<\/ud-information>/ ) { $meta{'settlement'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Communication channel">(.*?)<\/ud-information>/ ) { $meta{'channel'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Date[^"]*">(.*?)<\/ud-information>/ ) { $meta{'date'} = $1; if ( $meta{'date'} =~ /(..)-(..)-(....)/ ) { $year = $3; }; }; 
	if ( $metadata =~ /<ud-information attribute-name="Transcriber">(.*?)<\/ud-information>/ ) { $meta{'transcription'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Source">(.*?)<\/ud-information>/ ) { $meta{'source'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Original physical format">(.*?)<\/ud-information>/ ) { $meta{'orgformat'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Physical storage Id[^"]*">(.*?)<\/ud-information>/ ) { $meta{'orgid'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Code in CRPC">(.*?)<\/ud-information>/ ) { $meta{'crpc'} = $1; }; 
	if ( $metadata =~ /<ud-information attribute-name="Revisor">(.*?)<\/ud-information>/ ) { $meta{'transcription'} = $1; }; 
};

$personlist = "";  $pcnt = 0;
while ( $xml =~ /<speaker .*?<\/speaker>/gsmi ) {
	%prs = ();  $speaker = $&; # print $speaker;
	$pcnt++;
	
	if ( $speaker =~ /<abbreviation>(.*?)<\/abbreviation>/ ) { $prs{'id'} = $1; }; 
	if ( $speaker =~ /<sex value="(.*?)"\/>/ ) { $prs{'gender'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Name">(.*?)<\/ud-information>/ ) { $prs{'name'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Geographical origin">(.*?)<\/ud-information>/ ) { $prs{'nation'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Age">(.*?)<\/ud-information>/ ) { $prs{'age'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Education">(.*?)<\/ud-information>/ ) { $prs{'education'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Profession">(.*?)<\/ud-information>/ ) { $prs{'profession'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Residence">(.*?)<\/ud-information>/ ) { $prs{'residence'} = $1; }; 
	if ( $speaker =~ /<ud-information attribute-name="Role">(.*?)<\/ud-information>/ ) { $prs{'role'} = $1; }; 
	$personlist .= "
		<person id=\"".$prs{'id'}."\" n=\"$pcnt\" sex=\"".$prs{'gender'}."\" age=\"".$prs{'age'}."\" role=\"".$prs{'role'}."\">
			<name>".$prs{'name'}."</name>
			<nationality>".$prs{'nation'}."</nationality>
			<education>".$prs{'education'}."</education>
			<residence>".$prs{'residence'}."</residence>
			<socecStatus>".$prs{'profession'}."</socecStatus>
		</person>
	";
}; 

$teiHeader = "
<titleStmt>
	<title>".$meta{'title'}."</title>
	<respStmt>
		<resp n=\"project\">".$meta{'project'}."</resp>
		<resp n=\"transcription\">".$meta{'transcription'}."</resp>
		<resp n=\"revision\">".$meta{'revision'}."</resp>
	</respStmt>
</titleStmt>
<sourceDesc>
    <title>".$meta{'source'}."</title>
    <filename>".$relfilename."</filename>
</sourceDesc>
<profileDesc>
	<textDesc>
        <channel mode=\"s\">".$meta{'channel'}."</channel>
	</textDesc>
	<particDesc>
	 <listPerson>$personlist</listPerson>
	</particDesc>      
</profileDesc>
<recordingStmt>
	<date n=\"$year\">".$meta{'date'}."</date>
	<country>".$meta{'country'}."</country>
	<settlement>".$meta{'settlement'}."</settlement>
	<recording type=\"audio\">
 		<media mimeType=\"audio/wav\" url=\"Audio/$fid.wav\">
		<desc/> 
		</media>
	</recording>
	<note n=\"original storage format\">".$meta{'orgformat'}."</note>
	<note n=\"physical storage id\">".$meta{'orgid'}."</note>
</recordingStmt>
<notesStmt>
	<note n=\"comment\">".$meta{'comment'}."</note>
	<note n=\"topic\">".$meta{'topic'}."</note>
	<note n=\"CRPC id\">".$meta{'crpc'}."</note>
</notesStmt>
<revisionDesc>
	$morerev<change who=\"exb2tei\" when=\"$today\">Converted from EXMARaLDA file $relfilename</change></revisionDesc>

"; 
$teiHeader =~ s/>Unknown</></;
$teiHeader =~ s/"Unknown"/""/;
$teiHeader =~ s/ [^ ]+=""//;

# Check if the XML is valid?

print "TEI XML written to $outfolder$fid.xml";
open FILE, ">$outfolder$fid.xml";
binmode (FILE, ":utf8");
print FILE "<TEI>
<teiHeader>$teiHeader</teiHeader>

<text id=\"$fid\"$twho>
";
foreach my $key (sort {$a <=> $b} keys %s) {
	print FILE $s{$key};
};
print FILE "
</text>
</TEI>";
close FILE;