use utf8;
use Getopt::Long;

# Convert TextGrid file to TEITOK/XML
# TextGrid (https://www.fon.hum.uva.nl/praat/manual/TextGrid_file_formats.html) is an audio transcription format from Praat

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'export=s' => \$export, # which tiers to export
            'output=s' => \$output, # name of the output file - if empty STDOUT
            'morerev=s' => \$morerev, # More revision statements
            'file=s' => \$filename, # filename of the input
            'exclude=s' => \$exclude, # an optional pattern to define which utterances NOT to export
            'tiernames=s' => \$tiernames, # an optional list of names for the @who for each tier 1=John,3=Tim
            );

$\ = "\n"; $, = "\t";

binmode STDOUT, "utf8:";

if ( !$filename  ) { $filename = shift; };
if ( !$output ) { ( $output = $filename ) =~ s/\..+?$/.xml/; };

if ( $debug && $export ) { 
	print "Exporting tiers; $export"; 
	@tierlist = split ( ",", $export );
};

foreach $val ( split ( ',', $tiernames ) ) {
	( $num, $text ) = split ( ":", $val );
	$tiernamehash{$num} = $text;
	if ( $debug ) { print "Tier $num = $text"; };
};

open FILE, $filename;
# binmode  FILE, "utf8:";

while ( <FILE> ) {
	chop;
	$line = $_; $line =~ s/[\r\n]//g; $line =~ s/\0//g;

	if ( $line =~ /item\s+\[(\d+)\]:/ ) {
		$tiernum = $1; $intervalnum = 0;
		if ( $debug ) { print " -- NEW TIER $tiernum"; };
	} elsif ( $line =~ /intervals\s+\[(\d+)\]:/i ) {
		$intervalnum = $1;
		if ( $debug ) { print "   - INTERVAL $intervalnum for $tiernum"; };
	} elsif ( $intervalnum ) {
		if ( $line =~ /(.*) = (.*)/) {
			$key = $1; $val = $2; $key =~ s/[^a-z]//g; 
			$val =~ s/"//g; $val =~ s/\s+$//g; 			
			if ( $debug ) { print $tiernum, $key, $val; };
			$intervals{$tiernum}{'intervals'}{$intervalnum}{$key} = $val;
		};
	} elsif ( $tiernum ) {
		if ( $line =~ /(.*) = (.*)/) {
			$key = $1; $val = $2; $key =~ s/[^a-z]//g; 
			$val =~ s/"//g; $val =~ s/\s+$//g; 
			if ( $debug ) { print $tiernum, $key, $val; };
			$intervals{$tiernum}{$key} = $val;
		};
	} else {
		# No idea what to do with this line
		if ( $debug ) {
			print "? $line";
		};
	};
	
};

close FILE;

if ( !%intervals || scalar %intervals == 0 ) {
	print "Error: no intervals found"; exit;
};

while ( ( $tierid, $val ) = each ( %intervals ) ) {
	%tierdata = %{$val};
	if ( scalar @tierlist > 0 && !in_array($tierid, \@tierlist) ) {
		if ( $debug ) { print " - tier $tierid not specified for export"; };
	} else {
		if ( $debug ) { print "TIER $tierid: ".$tierdata{"name"}; };
		while ( ( $intid, $val2 ) = each ( $tierdata{'intervals'} ) ) {
			%intervaldata = %{$val2};
			$tiername = $tiernamehash{$tierid} or $tiername = $tierid;
			if ( $debug ) { print " $intid: ".$intervaldata{'xmin'}." = ".$intervaldata{'text'}; };
			if ( ( scalar @tierlist ) > 1 ) { $who = " who=\"$tiername\""; };
			$text = $intervaldata{'text'};
			if ( $text ne '' && ($exclude eq '' || $text !~ /$exclude/ ) ) { 
				$uarray{$intervaldata{'xmin'}} .= "<u start=\"".$intervaldata{'xmin'}."\" end=\"".$intervaldata{'xmax'}."\"$who>$text</u>"; 
			};
		};
	};
};

for $key ( sort {$a<=>$b} keys %uarray) {
	$teitxt .= $uarray{$key}."\n";
};

$fileid = $filename;
$fileid =~ s/.*\///;
$fileid =~ s/\.xml//;

# Produce the actual TEI
print "<TEI>
<teiHeader>
<notesStmt>
	<note n=\"orgfile\">$filename</note>
</notesStmt>
<revisionDesc>
	$morerev<change who=\"praat2tei\" when=\"$today\">Converted from Praat TextGrid</change></revisionDesc>
</teiHeader>
<text id=\"$fileid\">
$teitxt
</text>
</TEI>";

sub in_array ( $check, @list ) {
	$check = $_[0]; @list = @{$_[1]};
	
	foreach $elm ( @list ) {
		if ( $elm eq $check ) {
			return 1;
		};
	};
	
	return 0;
}