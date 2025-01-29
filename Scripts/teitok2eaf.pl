use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use XML::LibXML;
use Encode;

# Convert a TEITOK/XML file to EAF
# EAF (https://standards.clarin.eu/sis/views/view-spec.xq?id=SpecEAF) is an audio transcription from ELAN

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # vebose mode
            'help' => \$help, # help
            'file=s' => \$filename, # input file name
            'settings=s' => \$setfile, # input file name
            'output=s' => \$output, # output file name
            'outfolder=s' => \$outfolder, # Originals folder
            'ext=s' => \$ext, # Audio MIME
            'attlist=s' => \$attlist, # Attributes to put in the EAF
            'attskip=s' => \$attskip, # Attributes from settings.xml to skip
            );

$\ = "\n"; $, = "\t";

$parser = XML::LibXML->new(); 

if ( !$filename ) { $filename = shift; };
if ( $debug ) { $verbose = 1; };

if ( $help ) {
	print "Usage: perl teitok2eaf.pl [options] filename

Options:
	--verbose	verbose output
	--debug		debugging mode
	--file		filename to convert
	--output	EAF file to write to
	--outfolder	folder to write to
	--ext=s		audio extention
	--attlist=s	attributes to include in output
	--settings=s	settings.xml file
	--attskip=s	attributes to skip (from settings.xml)
	";
	exit;

};

$parser = XML::LibXML->new(); $tei = "";
eval {
	$tei = $parser->load_xml(location => $filename);
};
if ( !$tei ) { print "Invalid XML in $filename"; exit; };

%skipatts = ();
foreach $att ( split(",", $attskip) ) {
	$skipatts{$att} = 1;
};

if ( !$setfile ) { $setfile = "Resources/settings.xml" };
eval {
	$settings = $parser->load_xml(location => $setfile);
};
# Get the attributes to load into the EAF
if ( $attlist ) {
	# Use hard-coded attribute list
	%atts = ();
	foreach $att ( split(",", $attlist) ) {
		( $key, $val ) = split (":", $att);
		( $tkey, $okey ) = split ( '_', $key );
		if ( !$atts{$tkey} ) { $atts{$tkey} = (); };
		if ( !$val ) { $val = $okey; };
		$atts{$tkey}{$okey} = $val;
	};
	if ( $atts{'tok'} && !$atts{'tok'}{'id'} ) { $atts{'tok'}{'id'} = 'id';  };
	if ( !$atts{'u'} ) { $atts{'u'} = (); };
	if ( !$atts{'u'}{'id'} ) { $atts{'u'}{'id'} = 'id'; };
	if ( !$atts{'s'} ) { $atts{'s'} = (); };
	if ( !$atts{'s'}{'id'} ) { $atts{'s'}{'id'} = 'id';  };
} elsif ( $settings ) { 
	# attribute list from settings
	print " - reading attributes from settings";
	$atts{'tok'} = ();
	foreach $uatt ( $settings->findnodes("//xmlfile/sattributes/*/item") ) {
		$ptype = $uatt->parentNode->getAttribute("key");
		$key = $uatt->getAttribute("key");
		if ( $key eq 'pform' || $key eq 'start' || $key eq 'end' || $key eq 'tier' || $key eq 'who' || $skipatts{$key} ) { next; }; # Skip some attributes
		$atts{$ptype}{$key} = $key; 
	};
	if ( !$atts{'u'} ) { $atts{'u'} = (); };
	if ( !$atts{'u'}{'id'} ) { $atts{'u'}{'id'} = 'id';  };
	if ( !$atts{'s'} ) { $atts{'s'} = (); };
	if ( !$atts{'s'}{'id'} ) { $atts{'s'}{'id'} = 'id';  };
	$atts{'tok'} = ();
	foreach $form ( $settings->findnodes("//xmlfile/pattributes/*/item") ) {
		$key = $form->getAttribute("key");
		if ( $key eq 'pform' || $key eq 'start' || $key eq 'end' || $key eq 'tier' || $key eq 'who' || $skipatts{$key} ) { next; }; # Skip some attributes
		$atts{'tok'}{$key} = $key; 
	};
	if ( !$atts{'tok'}{'id'} ) { $atts{'tok'}{'id'} = 'id';  };
} else {
	# default attributes
	%atts = ( 
		"u" => { "id" => "id" },
		"tok" => { "id" => "id" },
	);
};

print "Loaded $filename";

$sameas = "sameAs";

$medianode = $tei->findnodes("//teiHeader//media/\@url");
if ( !$medianode ) { 
	print "TEITOK file does not contain any media - aborting";
	exit;
}; $media = $medianode->item(0)->value;
print "Media file: $media";
if ( !$ext && $media =~ /\.([^.]+)$/ ) { $ext = $1; } else { $ext = "x-wav"; };


$date = strftime "%Y-%m-%dT%H:%M:%S", localtime(); $author = "teitok2eaf"; 
$eaf = $parser->load_xml(string => "<ANNOTATION_DOCUMENT DATE=\"$date\" AUTHOR=\"$author\" FORMAT=\"3.0\" VERSION=\"3.6\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"http://www.mpi.nl/tools/elan/EAFv3.0.xsd\">
	<HEADER TIME_UNITS=\"milliseconds\">
		<MEDIA_DESCRIPTOR MEDIA_URL=\"$media\" MIME_TYPE=\"audio/$ext\"/>
	</HEADER>
	<TIME_ORDER/>
</ANNOTATION_DOCUMENT>
");

$langnode = $tei->findnodes("//langUsage/language");
if ( $langnode ) { 
	$lang = ""; # Get direct children text content
	for my $child_node ($langnode->item(0)->childNodes()) {
	   next if $child_node->nodeType != XML_TEXT_NODE;
	   $lang .= $child_node;
	}
	$langcode = $langnode->item(0)->getAttribute('ident') or $langcode = $lang;
	if ( $langcode && !$lang ) { $lang = $langcode; };
	$tmp = XML::LibXML::Element->new( "LANGUAGE" );
	$tmp->setAttribute('LANG_ID', $langcode);
	$tmp->setAttribute('LANG_LABEL', $lang);
	$eaf->firstChild->appendChild($tmp);
	$countrynode = $langnode->item(0)->findnodes("./country");
	if ( $countrynode ) {
		$country = $countrynode->item(0)->textContent;
		$countrycode = $countrynode->item(0)->getAttribute('key') or $countrycode = $country;
		if ( $countrynode && !$country ) { $country = $countrynode; };
		$tmp = XML::LibXML::Element->new( "LOCALE" );
		$tmp->setAttribute('COUNTRY_CODE', $countrycode);
		$tmp->setAttribute('LANGUAGE_CODE', $langcode);
		$eaf->firstChild->appendChild($tmp);
	};
};

# Add the linguistic types
# LANGUAGE, CONSTRAINT, CONTROLLED_VOCABULARY, LEXICON_REF, REF_LINK_SET, EXTERNAL_REF
$tmp = XML::LibXML::Element->new( "LINGUISTIC_TYPE" );
$tmp->setAttribute('LINGUISTIC_TYPE_ID', 'u');
$tmp->setAttribute('GRAPHIC_REFERENCES', 'false');
$tmp->setAttribute('TIME_ALIGNABLE', 'true');
$eaf->firstChild->appendChild($tmp);
while ( ( $key, $val ) = each ( %{$atts{'u'}} ) ) {
	$tmp = XML::LibXML::Element->new( "LINGUISTIC_TYPE" );
	$tmp->setAttribute('LINGUISTIC_TYPE_ID', "u_$val");
	$tmp->setAttribute('GRAPHIC_REFERENCES', 'false');
	$tmp->setAttribute('TIME_ALIGNABLE', 'false');
	$tmp->setAttribute('CONSTRAINTS', 'Symbolic_Association');
	$eaf->firstChild->appendChild($tmp);
};
$tmp = XML::LibXML::Element->new( "LINGUISTIC_TYPE" );
$tmp->setAttribute('LINGUISTIC_TYPE_ID', 'tok');
$tmp->setAttribute('GRAPHIC_REFERENCES', 'false');
$tmp->setAttribute('TIME_ALIGNABLE', 'true');
$eaf->firstChild->appendChild($tmp);
while ( ( $key, $val ) = each ( %{$atts{'tok'}} ) ) {
	$tmp = XML::LibXML::Element->new( "LINGUISTIC_TYPE" );
	$tmp->setAttribute('LINGUISTIC_TYPE_ID', "tok_$val");
	$tmp->setAttribute('GRAPHIC_REFERENCES', 'false');
	$tmp->setAttribute('TIME_ALIGNABLE', 'false');
	$tmp->setAttribute('CONSTRAINTS', 'Symbolic_Association');
	$eaf->firstChild->appendChild($tmp);
};

%times = (); %types = (); %indexes = ();
# First check if there are any nodes with a @start and @end
# and create a timeline
foreach $node ( $tei->findnodes("//text//*[\@start and \@end]") ) {
	$start = $node->getAttribute("start");
	$end = $node->getAttribute("end");
	$nodetype = $node->getName()."";
	$tcnt = $times{$start} or $tcnt = 0;
	$times{$start} = $tcnt + 1;
	$tcnt = $times{$start} or $tcnt = 0;
	$times{$end} = $tcnt + 1;
	$tcnt = $types{$nodetype} or $tcnt = 0;
	$types{$nodetype} = $tcnt + 1;
};

$ik = 0;
$timeorder = $eaf->findnodes("//TIME_ORDER")->item(0);
foreach $key (sort { $a <=> $b} keys %times ) {
	$timeslot = XML::LibXML::Element->new( "TIME_SLOT" );
	$timeorder->appendChild($timeslot);
	$timeid = "ts".++$ik;
	$time2id{$key} = $timeid;
	$timeslot->setAttribute("TIME_SLOT_ID", $timeid);
	$timeslot->setAttribute("TIME_VALUE", $key*1000);
};

$tiers = (); $anns = 0;
if ( $types{'u'} ) { $stype = "u"; } elsif ( $types{'s'} ) { $stype = "s"; };
if ( $stype ) {
	print "Utterance type: $stype";
	$tiers{'u'} = XML::LibXML::Element->new( "TIER" );
	$tiers{'u'}->setAttribute('TIER_ID', 'u');
	$tiers{'u'}->setAttribute('LINGUISTIC_TYPE_REF', 'u');
	while ( ( $key, $val ) = each ( %{$atts{'u'}} ) ) {
		$tiers{"u_$val"} = XML::LibXML::Element->new( "TIER" );
		$tiers{"u_$val"}->setAttribute('TIER_ID', "u_$val");
		$tiers{"u_$val"}->setAttribute('LINGUISTIC_TYPE_REF', "u_$val");
		$tiers{"u_$val"}->setAttribute('PARENT_REF', "u");
	};
	foreach $u ( $tei->findnodes("//text//$stype") ) {
		$who = $u->getAttribute('who');
		if ( $who ) {
			if ( !$tiers{"u\@$who"} ) {
				$tiers{"u\@$who"} = XML::LibXML::Element->new( "TIER" );
				$tiers{"u\@$who"}->setAttribute('TIER_ID', "u\@$who");
				$tiers{"u\@$who"}->setAttribute('LINGUISTIC_TYPE_REF', 'u');
				$tiers{"u\@$who"}->setAttribute('PARTICIPANT', $who);
				$eaf->firstChild->appendChild($tiers{"u\@$who"});
				while ( ( $key, $val ) = each ( %{$atts{'u'}} ) ) {
					$tiers{"u_$val\@$who"} = XML::LibXML::Element->new( "TIER" );
					$tiers{"u_$val\@$who"}->setAttribute('TIER_ID', "u_$val\@$who");
					$tiers{"u_$val\@$who"}->setAttribute('LINGUISTIC_TYPE_REF', "u_$val");
					$tiers{"u_$val\@$who"}->setAttribute('PARENT_REF', "u");
					$eaf->firstChild->appendChild($tiers{"u_$val\@$who"});
				};
			};
			$tier = $tiers{"u\@$who"};
		} else {
			$tier = $tiers{'u'};
		};
		$utt = XML::LibXML::Element->new( "ANNOTATION" );
		$tier->appendChild($utt);
		$start = $u->getAttribute("start");
		$end = $u->getAttribute("end");
		if ( $start && $end ) {
			$annid = "a".++$anns;
			$dutt = XML::LibXML::Element->new( "ALIGNABLE_ANNOTATION" );
			$utt->appendChild($dutt);
			$dutt->setAttribute("ANNOTATION_ID", $annid);
			$dutt->setAttribute("TIME_SLOT_REF1", $time2id{$start});
			$dutt->setAttribute("TIME_SLOT_REF2", $time2id{$end});
			$utext = $u->getAttribute('text') or $u->textContent; 
			$utext =~ s/^\s+|\s+$//g;
			$utext =~ s/\s+/ /g;
			$duttt = XML::LibXML::Element->new( "ANNOTATION_VALUE" );
			$dutt->appendChild($duttt);
			$duttt->appendText($utext);
			$refid = $annid;
			while ( ( $key, $val ) = each ( %{$atts{'u'}} ) ) {
				$vval = $u->getAttribute($key);
				if ( $who ) { $dtiername = "u_$val\@$who"; } else { $dtiername = "u_$val"; };
				$dtier = $tiers{$dtiername};
				if ( $vval ) {
					$dann = XML::LibXML::Element->new( "ANNOTATION" );
					$dtier->appendChild($dann);
					$annid = "a".++$anns;
					$dref = XML::LibXML::Element->new( "REF_ANNOTATION" );
					$dann->appendChild($dref);
					$dref->setAttribute("ANNOTATION_ID", $annid);
					$dref->setAttribute("ANNOTATION_REF", $refid);
					$drefv = XML::LibXML::Element->new( "ANNOTATION_VALUE" );
					$dref->appendChild($drefv);
					$drefv->appendText($vval);
				};
			};
		};
		
		if ( !$u->findnodes(".//*[\@start]") ) {
			# Utterance without aligned tokens below
			next; 
		}
		if ( $who ) { $toktierid = "tok\@$who"; } else { $toktierid = "tok"; }; 
		if ( !$tiers{$toktierid} ) {
			$tiers{$toktierid} = XML::LibXML::Element->new( "TIER" );
			$tiers{$toktierid}->setAttribute('TIER_ID', $toktierid);
			$tiers{$toktierid}->setAttribute('LINGUISTIC_TYPE_REF', 'tok');
			while ( ( $key, $val ) = each ( %{$atts{'tok'}} ) ) {
				$tiers{"tok_$val"} = XML::LibXML::Element->new( "TIER" );
				$tiers{"tok_$val"}->setAttribute('TIER_ID', "tok_$val");
				$tiers{"tok_$val"}->setAttribute('LINGUISTIC_TYPE_REF', "tok_$val");
				$tiers{"tok_$val"}->setAttribute('PARENT_REF', "tok");
			};
			$eaf->firstChild->appendChild($tiers{$toktierid});
			if ( $who ) { 
				$tiers{$toktierid}->setAttribute('PARTICIPANT', $who); 
				while ( ( $key, $val ) = each ( %{$atts{'tok'}} ) ) {
					$tiers{"tok_$val\@$who"} = XML::LibXML::Element->new( "TIER" );
					$tiers{"tok_$val\@$who"}->setAttribute('TIER_ID', "tok_$val\@$who");
					$tiers{"tok_$val\@$who"}->setAttribute('LINGUISTIC_TYPE_REF', "tok_$val");
					$tiers{"tok_$val\@$who"}->setAttribute('PARENT_REF', "tok");
					$eaf->firstChild->appendChild($tiers{"tok_$val\@$who"});
				};
			};
		}; $tier = $tiers{$toktierid};
		
		if ( !$u->findnodes(".//tok") && $u->getAttribute($sameas) ) {
			$sameasis = $u->getAttribute($sameas);
			$sameasis =~ 
			print $sameasis; exit;
		} else {
			# @tokens = $u->getChildNodes();
			@tokens = $u->findnodes(".//*[name() = 'tok' or name() = 'gap' or name() = 'pause']");
		};
		foreach $tok ( @tokens ) {
			if ( $tok->nodeType != XML_ELEMENT_NODE ) { 
				# Skip text nodes (spaces)
				next; 
			};
			
			$annid = "a".++$anns;
			$start = $tok->getAttribute("start"); if ( !$start ) { $start = $lastend; };
			$end = $tok->getAttribute("end"); if ( !$end ) { $end = $start; };
	
			$toktxt = $tok->textContent;
			$wd = XML::LibXML::Element->new( "ANNOTATION" );
			$tier->appendChild($wd);
			$dwd = XML::LibXML::Element->new( "ALIGNABLE_ANNOTATION" );
			$wd->appendChild($dwd);
			$dwd->setAttribute("ANNOTATION_ID", $annid);
			$dwd->setAttribute("TIME_SLOT_REF1", $time2id{$start});
			$dwd->setAttribute("TIME_SLOT_REF2", $time2id{$end});
			$toktxt =~ s/^\s+|\s+$//g;
			$toktxt =~ s/\s+/ /g;
			$dwdd = XML::LibXML::Element->new( "ANNOTATION_VALUE" );
			$dwd->appendChild($dwdd);
			$dwdd->appendText($toktxt);
			$refid = $annid;
			while ( ( $key, $val ) = each ( %{$atts{'tok'}} ) ) {
				$vval = $tok->getAttribute($key);
				if ( !$vval ) {  $vval = ""; };
				if ( $who ) { $dttiername = "tok_$val\@$who"; } else { $dttiername = "tok_$val"; };
				$awd = XML::LibXML::Element->new( "ANNOTATION" );
				$tiers{$dttiername}->appendChild($awd);
				$adwd = XML::LibXML::Element->new( "REF_ANNOTATION" );
				$awd->appendChild($adwd);
				$annid = "a".++$anns;
				$adwd->setAttribute("ANNOTATION_ID", $annid);
				$adwd->setAttribute("ANNOTATION_REF", $refid);
				$adwdd = XML::LibXML::Element->new( "ANNOTATION_VALUE" );
				$adwd->appendChild($adwdd);
				$adwdd->appendText($vval);
			};			
			$lastend = $end;		
		};
	};

	# Add all filled tiers without a WHO
	foreach $key1 ( split(',', 'u,s,tok') ) {
		$tiername = $key1;
		if ( $tiers{$tiername} && $tiers{$tiername}->childNodes() ) {
			$eaf->firstChild->appendChild($tiers{$tiername});
		};
		while ( ( $key2, $val2 ) = each ( %{$atts{$key1}} ) ) {
			$tiername = $key1.'_'.$key2;
			if ( $tiers{$tiername} && $tiers{$tiername}->childNodes() ) {
				$eaf->firstChild->appendChild($tiers{$tiername});
			};
		};
	};
	
} elsif ( $types{'tok'} ) {
	# Tokens without utterances - go through them individually
	# Yet to be implemented
};


if ( $output eq 'STDOUT') {
	## use STDOUT
} elsif ( !$output && $outfolder ) { 
	( $output = $filename ) =~ s/\.xml/.eaf/; 
	if ( $outfolder ) { 
		$output =~ s/.*\//$outfolder\//;
	};
} else {
	( $ofldr = $output ) =~ s/[^\/]+$//;
	if ( $oflder ) {
		if ( $debug ) { print "Creating $ofldr when needed"; };
		`mkdir -p $ofldr`;
	};
};

if ( !$tei->findnodes("//tok") ) {
	print "Error: cannot convert untokenized files to CoNNL-U";
	exit;
};

if ( $output ) {
	print "Writing converted file to $output\n";
	open OUTFILE, ">$output";
} else {
	*OUTFILE = STDOUT;
};
binmode(OUTFILE, ":utf8");
print OUTFILE $eaf->toString(1);
close OUTFILE;
