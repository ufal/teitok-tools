# hOCR2TEI.pl
# convert a hOCR (pe from tesseract) to TEI
# (c) Maarten Janssen, 2016

use utf8;

$filename = shift;

$/ = undef;
open FILE, $filename;
binmode(FILE, ":utf8");
$text = <FILE>;
close FILE;

$text =~ s/.*<body>//smi;
$text =~ s/<\/body>.*//smi;

# Convert words
while ( $text =~ /<span class='ocrx_word'[^>]*>(.*?)<\/span>/ ) {
	$from = $&; $inner = $1;
	$bbox = ""; if ( $from =~ /bbox (\d+ \d+ \d+ \d+)/ ) { $bbox = $1; };

	$to = "<tok bbox=\"$bbox\">$inner</tok>";
	
	$text =~ s/\Q$from\E/$to/;
};

# Convert pages
while ( $text =~ /<div class='ocr_page'[^>]*>/ ) {
	$from = $&;
	$bbox = ""; if ( $from =~ /bbox (\d+ \d+ \d+ \d+)/ ) { $bbox = $1; };
	$img = ""; if ( $from =~ /image "([^"]+)"/ ) { $img = $1; };

	$to = "<pb bbox=\"$bbox\" facs=\"$img\"/>";
	
	$text =~ s/\Q$from\E/$to/;
};

# Convert lines
while ( $text =~ /<span class='ocr_line'[^>]*>/ ) {
	$from = $&;
	$bbox = ""; if ( $from =~ /bbox (\d+ \d+ \d+ \d+)/ ) { $bbox = $1; };

	$to = "<lb bbox=\"$bbox\"/>";
	
	$text =~ s/\Q$from\E/$to/;
};

# Convert paragraphs
while ( $text =~ /<p class='ocr_par'[^>]*>/ ) {
	$from = $&; 
	$bbox = ""; if ( $from =~ /bbox (\d+ \d+ \d+ \d+)/ ) { $bbox = $1; };

	$to = "<p bbox=\"$bbox\">";
	
	$text =~ s/\Q$from\E/$to/;
};

# Split off punctuation marks
$text =~ s/(\p{isPunct})<\/tok>/<\/tok><tok>\1<\/tok>/g;
$text =~ s/(<tok[^>]*>)(\p{isPunct})/<tok>\2<\/tok>\1/g;

# Clean non-needed stuff
$text =~ s/<div class='ocr_carea'[^>]*>//g;
$text =~ s/<\/div>//g;
$text =~ s/<\/span>//g;

$tei = "<TEI>
<teiHeader>
</teiHeader>
<text>
$text
</text>
</TEI>";

binmode(STDOUT, ":utf8");
print $tei;