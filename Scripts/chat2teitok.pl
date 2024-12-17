use utf8;
use XML::LibXML;
use Data::Dumper;
use Getopt::Long;
use Encode qw(decode encode);

# Conversion from a CHAT transcript file (.cha) to the TEITOK format
# Chat (https://ceapp.la.psu.edu/node/44) is a transcription format for spoken data
# Maarten Janssen, 2020

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'output=s' => \$output, # name of the output file - if empty STDOUT
            'morerev=s' => \$morerev, # More revision statements
            'file=s' => \$filename, # filename of the input
            'options=s' => \$options, # format of the transcription
            );

$\ = "\n"; $, = "\t";

binmode STDOUT, "utf8:";

if ( !$filename  ) { $filename = shift; };
if ( !$output ) { ( $output = $filename ) =~ s/\..+?$/.xml/; };

$parser = XML::LibXML->new(); $doc = "";
$doc = XML::LibXML::Document->new(1.0, "UTF-8");
$root = $doc->createElement("TEI");
$doc->setEncoding("UTF8");
$doc->setDocumentElement($root);
$teiheader = $doc->createElement("teiHeader"); $doc->firstChild->addChild($teiheader);
$text = $doc->createElement("text"); $doc->firstChild->addChild($text);

$xps{'Comment'} = ["/TEI/teiHeader/notesStmt", "note"];
$xps{'Title'} = ["/TEI/teiHeader/fileDesc/titleStmt", "title"];
$xps{'Date'} = ["/TEI/teiHeader/fileDesc/titleStmt", "date"];
$xps{'Languages'} = ["/TEI/teiHeader/profileDesc/langUsage", "language", "ident"];
$xps{'Language'} = ["/TEI/teiHeader/profileDesc/langUsage", "language", "ident"];
$xps{'Location'} = ["/TEI/teiHeader/recordingStmt/recording", "location"];
$xps{'Transcriber'} = ["/TEI/teiHeader/fileDesc/titleStmt/respStmt", "resp", "", "n", "Transcription"];
$xps{'Creator'} = ["/TEI/teiHeader/fileDesc/titleStmt/respStmt", "resp", "", "n", "Creator"];
$xps{'Types'} = ["/TEI/teiHeader/profileDesc/textClass/keywords", "term", "", "type", "genre"];
$xps{'Subject'} = ["/TEI/teiHeader/profileDesc/textClass/keywords", "term", "", "type", "genre"];
$xps{'Publisher'} = ["/TEI/teiHeader/fileDesc/publicationStmt", "publisher"];
$xps{'PID'} = ["/TEI/teiHeader/fileDesc/publicationStmt", "idno", "", "type", "handle"];

$elms{'G'} = ["milestone", "n"];
$elms{'New Episode'} = ["milestone", "n"];

# @ID: language|corpus|code|age|sex|group|SES|role|education|custom|
@ids = ("langKnowledge/langKnown[\@level=\"first\"]","*corpus","*code","\@age","\@sex","./note[\@n=\"group\"]","./note[\@n=\"ethnicity\"]","*role","./education","./note[\@n=\"custom\"]");

$convs{'CA'} = "CLAN";
$convs{'heritage'} = "Heritage";

$/ = undef;	
open FILE, $filename;
binmode  FILE, "utf8:";
$rawtext = <FILE>;
close FILE;

$rawtext =~ s/\n\s+(?!\(\d)/ /g;

if ( !$options && $rawtext !~ /\@Options/ ) {
	if ( $rawtext =~ /(\d+)_(\d+)/ ) { $options = "CA";  };
};

foreach $line  ( split ( "\n", $rawtext ) ) {
	$line =~ s/[\r\n]//g; $line =~ s/\0//g;

	if ( $line =~ /@([^:]+):\s*(.*)/ ) {
		# Metadata line	
		$fld = $1; $orgval = $2; 
		$val = sanitize($orgval);
		if ( $fld eq 'Options' ) {
			if ( !$transform ) { $transform = $val; };
		} elsif ( $fld eq 'Participants' ) {
			$basenode = makenode($doc, "/TEI/teiHeader/profileDesc/particDesc/listPerson");
			foreach $pfld ( split ( ", ", $val ) ) {
				( $code, $name, $role ) = split(" ", $pfld);
				$person{$code} = $doc->createElement("person"); 
				$person{$code}->setAttribute("id", $code);
				$person{$code}->setAttribute("role", $role);
				$person{$code}->appendText($name);
				$basenode->addChild($person{$code});
			};
		} elsif ( $fld eq 'ID' ) {
			@flds = split("[|]", $val);
			if ( !$person{$flds[2]} ) { print "No such person in $val: ".$flds[2]; exit; };
			for ( $i=0; $i<scalar @flds; $i++ ) { 
				if ( $flds[$i] && substr($ids[$i],0,1) ne "*" ) {
					$node = makenode($person{$flds[2]}, "./".$ids[$i]);
					if ( $node->nodeType == 2 ) {
						$node->parentNode->setAttribute($node->getName(), $flds[$i]);
					} else {
						$node->appendText($flds[$i]);
					};
				};
			};
		} elsif ( $fld eq 'Media' ) {
			($recurl, $type) = split(", ", $val);
			$media = makenode($doc, "/TEI/teiHeader/recordingStmt/recording/media");
			if ( $recurl !~ /\./ ) {
				if ( $type eq "audio" ) { 
					$recurl .= ".mp3"; 
					$media->setAttribute("mimeType", "audio/mp3");
				} elsif ( $type eq "video" ) { 
					$recurl .= ".mpg"; 
					$media->setAttribute("mimeType", "video/mpg");
				};
			};
			$media->setAttribute("url", $recurl);
		} elsif ( $xps{$fld} ) {
			($base, $elm, $att, $satt, $sval) = @{$xps{$fld}};
			if ( $intext ) { 
				$satt = $att or $satt = $elm;
				if ( !$milestone ) {
					$milestone = $doc->createElement("milestone"); $text->addChild($milestone);
				};
				if ( $milestone->getAttribute($satt) ) { $val = $milestone->getAttribute($satt)."; ".$val};
				$milestone->setAttribute(lc($satt), $val);
			} else {
				utf8::downgrade($val);
				$basenode = makenode($doc, $base);
				$valnode = $doc->createElement($elm); 
				$basenode->addChild($valnode);
				if ( $satt ) {
					$valnode->setAttribute($satt, $sval);
				};
				if ( $att ) {
					$valnode->setAttribute($att, $val);
				} else {
					$valnode->appendText($val);
				};
			};
		} elsif ( $elms{$fld} ) {
			($elm, $att) = @{$elms{$fld}};
			$milestone = $doc->createElement($elm); $text->addChild($milestone);
			$milestone->setAttribute($att, $val);
			$intext = 1;
		} else {
			# Print unknown field
			$basenode = makenode($doc, "/TEI/teiHeader/notesStmt");
			$valnode = $doc->createElement("note"); 
			$valnode->setAttribute("n", $fld);
			$valnode->appendText($val);
			$basenode->addChild($valnode);
		};
	} elsif ( $line =~ /\*([^:]+):\s*(.*)/ ) {
		# Transcription line
		$who = $1; $trans = $2; $intext = 1;
		if ( $convs{$options} ) {
			$transxml = convutt($trans, $options);
			$uttxml = $parser->load_xml(string => $transxml, { no_blanks => 1 });
			$utt = $uttxml->firstChild;
			$text->addChild($utt);
		} else {
			$utt = $doc->createElement("u"); $text->addChild($utt);
			$utt->appendText($trans);
		};
			$utt->setAttribute("who", $who);
	} elsif ( $line =~ /\%([^:]+):\s*(.*)/ ) {
		# Transcription line
		$channel = $1; $val = $2; 
		$note = $doc->createElement("note"); $text->addChild($note);
		$note->appendText($val);
		$note->setAttribute("n", $channel);
	} else {
		# Continuation of a transcription line?
		if ( $debug ) {
			print "Line? $line";
		};
	};
	
};


$basename = $filename;
$basename =~ s/.*\///;
$basename =~ s/\.[^.]+$//;

# $doc->setEncoding();
$teixml = $doc->toString(1);
$teixml =~ s/<\?.*?\?>//;

print "Writing output to $output";
open OUTFILE, ">$output";
print OUTFILE $teixml;
close OUTFILE;

sub convutt ( $trans, $format ) {
	( $trans, $format ) = @_;

	# Protect any codes for XML
	$trans =~ s/&/&amp;/g;
	$trans =~ s/</&lt;/g;
	$trans =~ s/>/&gt;/g;
	
	if ( $trans =~ s/(\d+)_(\d+)// ) {
		$begin = ($1/1000); $end = ($2/1000);
		$timing = " begin=\"$begin\" end=\"$end\"";  
	};
	if ( $format eq 'CA' ) {
	
		# print $trans;
		
	
	} elsif ( $format eq 'heritage' ) {
		$trans =~ s/&lt;(.*?)&gt;/<del reason="reformulation">\1<\/del>/g;
		$trans =~ s/&amp;([^ <>]+)/<del reason="truncation">\1<\/del>/g;

		$trans =~ s/\((.*?)\)/<ex>\1<\/ex>/g;

		$trans =~ s/([^ ]+)@([^ ]+)/<sic n="\2">\1<\/sic>/g;

		$trans =~ s/xxx/<gap reason="unintelligible">xxx<\/gap>/g;
		$trans =~ s/www/<gap reason="non-transcribed"\/>/g;

		$trans =~ s/\[\/\]/<pause type="short"\/>/g;
		$trans =~ s/\[\/\/\]/<pause type="long"\/>/g;
	}; 
	
	
	return "<u$timing>$trans</u>";
};

sub in_array ( $check, @list ) {
	$check = $_[0]; @list = @{$_[1]};
	
	foreach $elm ( @list ) {
		if ( $elm eq $check ) {
			return 1;
		};
	};
	
	return 0;
}

sub makenode ( $xml, $xquery ) {
	my ( $xml, $xquery ) = @_;
	$tmp = $xml->findnodes($xquery); 
	if ( $tmp ) { 
		if ( $debug ) { print "Node exists: $xquery"; };
		return $tmp->item(0);
	} else {
		if ( $xquery =~ /^(.*)\/(.*?)$/ ) {
			my $parxp = $1; my $thisname = $2;
			my $parnode = makenode($xml, $parxp);
			$thisatts = "";
			if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
				$thisname = $1; $thisatts = $2;
			};
			if ( $thisname =~ /^@(.*)/ ) {
				$attname = $1;
				$parnode->setAttribute($attname, '');
				foreach $att ( $parnode->attributes() ) {
					if ( $att->getName eq $attname ) {
						return $att;
					};
				};
			} else {
				$newchild = XML::LibXML::Element->new( $thisname );
			
				# Set any attributes defined for this node
				if ( $thisatts ne '' ) {
					if ( $debug ) { print "setting attributes $thisatts"; };
					foreach $ap ( split ( " and ", $thisatts ) ) {
						if ( $ap =~ /\@([^ ]+) *= *"(.*?)"/ ) {
							$an = $1; $av = $2; 
							$newchild->setAttribute($an, $av);
						};
					};
				};

				if ( $debug ) { print "Creating node: $xquery ($thisname)"; };
				$parnode->addChild($newchild);
			};
			
		} else {
			print "Failed to find or create node: $xquery";
		};
	};
};

sub sanitize ( $string ) {
	$string = @_[0];
	
	$string =~ s/[^\x09\x0A\x0D\x20-\xFF\x85\xA0\uD7FF\uE000-\uFDCF\uFDE0-\uFFFD]//gm;
	
	return $string;
};