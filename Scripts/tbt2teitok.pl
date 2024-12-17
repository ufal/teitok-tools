use Getopt::Long;

# Convert a TBR file to TEITOK/XML
# TBT is a format for interlinear glossed text from the Linguistic Toolbox

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # which UDPIPE model to use
            'output=s' => \$output, # which UDPIPE model to use
            'morerev=s' => \$morerev, # language of input
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };
( $basename = $filename ) =~ s/.*\///; $basename =~ s/\..*//;
if ( !$output ) { $output = $basename.".xml"; };

open FILE, $filename;
binmode (FILE, ":encoding(UTF-8)");
while ( <FILE> ) {
	if ( /^\\([^ ]+) *(.*)/ ) { 
		$code = $1; 
		$content = $2; 
		if ( $debug ) { print "*", $code, $content; };
		$content =~ s/&/&amp;/g;
		$c{$code} = $content;	
	} else {
		# Parse the phrase
		$txt = $c{'tx'}; $p=0; $w=0; $toklist = ""; $pi[$w] = $p; $in = 1;
		if ( $debug ) { print "Parsing: $txt (".length($txt).")"; };
		for ( $i=0; $i<length($txt); $i++ ) {
			if ( $debug > 1 ) { print $i, substr($txt,$i,1); };
			if ( !$in && substr($txt,$i,1) ne ' ' ) {
				$w++; $pi[$w] = $i; $in = 0; $p = $i;
				$in = 1;
			} elsif ( $in && substr($txt,$i,1) eq ' ' ) {
				$in = 0;
			};
		};
		$w++; $pi[$w] = length($txt);

		# Set the language
		if ( $c{'lang'} ) { $lang = "lang=\"".$c{'lang'}."\""; };

		# Determine the morpheme levels to be treated
		while ( ( $key, $val ) = each ( %c ) ) {
			if ( $key eq 'tx' || ( substr($c{$key},$pi[1]-1,1) ne ' ' && scalar @pi > 1 ) ) { 
				if ( $debug ) { print "Ignoring: $key"; };
				next; 
			}; 
			if ( $debug ) { print "Morphemic tier: $key"; };
			push(@ml, $key);
		};		
		
		for ( $i=0; $i < scalar @pi-1; $i++ ) {
			$pos = $pi[$i]; $length = $pi[$i+1]-$pos;
			$word = substr($c{'tx'}, $pos, $length);
			$word =~ s/\s+$//;
			if ( $debug ) { print $pos, $length, $word; };
			
			# From the first morpheme level tag, get the morpheme positions for this word	
			$p=$pos; $m=0; $mi[$m] = $p; $in = 1;
			$mtxt = substr($c{$ml[0]}, $pos, $length );
			if ( $debug ) { print "Parsing morph: $mtxt (".length($mtxt).")"; };
			for ( $j=$pos; $j<$length; $j++ ) {
				if ( $debug > 1 ) { print $j, substr($mtxt,$j,1); };
				if ( !$in && substr($mtxt,$j,1) ne ' ' ) {
					$m++; $mi[$m] = $j; $in = 0; $p = $j;
					$in = 1;
				} elsif ( $in && substr($mtxt,$j,1) eq ' ' ) {
					$in = 0;
				};
			};
			$m++; $mi[$m] = $pos+length($mtxt);
			
			$morphs = "";
			if ( $mi[1] ) {
				for ( $j=0; $j < scalar @mi-1; $j++ ) {
					$mpos = $mi[$j]; $mlength = $mi[$j+1]-$mpos;
					$matts = "";
					foreach $mx ( @ml ) {
						$morph = substr($c{$mx}, $mpos, $mlength);
						$morph =~ s/\s+$//;
						if ( $debug ) { print $mx, $mpos, $mlength, $morph; };
						$matts .= " $mx=\"$morph\"";
					};
					
					if ( $matts ne "" ) { $morphs .= "<morph$matts/>"; };
				};
			};			
			undef(@mi);
			 
			$toklist .= "<tok>$word$morphs</tok> ";
		};
		
		if ( $txt ) {
			$xml .= "\n<s $lang original=\"".$c{'tx'}."\">".$toklist."</s>";
		};
		
		undef(%c); $txt = ""; $lang = ""; undef(@pi); undef(@ml);
		if ( $debug ) { print; };
	};
};
close FILE;

print "Writing output to $output";
open OUTFILE, ">$output";
print OUTFILE "<TEI>
<teiHeader/>
<text>
$xml
</text>
</TEI>";
close OUTFILE;