$baseurl = shift;
if ( $baseurl =~ /https?:\/\/(.*?)(\/.*)/ ) { $server = $1; $path = $2; };

print "<crp server=\"$server\" path=\"$path\">\n";
while ( <> ) {

	$line = $_;
	if ( $line =~ /^<\?/ ) {
		next; # Skip the XML definition
	} elsif ( $line =~ /^<\/?corpus[ >]/ ) {
		next; # Skip the corpus
	} elsif ( $line =~ /^<\/[^>]+_/ ) {
		next; # Skip ends of a_b attributes
	} elsif ( $line =~ /^<\// ) {
		print $line;
	} elsif ( $line =~ /^<([^ ]+)_([^ ]+) (.*)>/ ) {
		$tag = $1; $att = $2; $val = $3;
		if ( $tag ne $otg ) { 
			print "Oops"; exit; 
		} elsif ( $tag eq "text" && $att eq "id" ) {
			$valid = $val; $valid =~ s/\..*//; $valid =~ s/.*\///; 
			
			$org = $val; $org =~ s/xmlfiles\///; # $org = $baseurl.$val; 
			
			$atts .= " $att=\"$valid\"";
		} else {
			$atts .= " $att=\"$val\"";
		};
	} elsif ( $line =~ /^<([^ _]+)>/ ) {
		if ( $otg ) { 
			print "<$otg$atts>\n"; 
		};		
		$otg = ""; $atts = "";
		$otg = $1;
	} else {
		if ( $otg ) { 
			print "<$otg$atts>\n"; 
		};		
		$otg = ""; $atts = "";
		print $line;
	};

	
};
print "</crp>";
