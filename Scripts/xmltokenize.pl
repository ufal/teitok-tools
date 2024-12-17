use Encode qw(decode encode);
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use HTML::Entities;
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

# Script to tokenize XML files inline; splits on spaces, and splits off UTF punctuation chars at the beginning and end of a token
# Splits existing XML tags if they get broken by the tokens
# Can split sentences as well, where a sentence boundary is a sentence-final character as its own token
# (c) Maarten Janssen, 2014

$scriptname = $0;

 GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'enumerate' => \$enumerate, # provide a unique ID to each token
            'filename=s' => \$filename, # language of input
            'textnode=s' => \$mtxtelm, # what to use as the text to tokenize
            'tok=s' => \$toknode, # what to use as a token
            'exclude=s' => \$exclude, # elements not to tokenize
            'segment=i' => \$sentsplit, # split into sentences (1=yes, 2=only)
            );

$\ = "\n"; $, = "\t";

if ( $toknode eq '' ) { $toknode = 'tok'; };

if ( $filename eq '' ) {
	$filename = shift;
};

if ( $filename eq '' ) {
	print " -- usage: xmltokenize.pl --filename=[fn]"; exit;
};

if ( !-e $filename ) {
	print " -- no such file $filename"; exit;
};

binmode ( STDOUT, ":utf8" );

$/ = undef;
open FILE, $filename;
binmode ( FILE, ":utf8" );
$rawxml = <FILE>;
close FILE;

# Temporarily turn off namespace
$rawxml =~ s/xmlns=/xmlnsoff=/;

# Check if this is valid XML and get document type
$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(string => $rawxml, {  load_ext_dtd => 0 });
};
if ( !$doc ) { print "Invalid XML in $filename"; exit; };
$filetype = $doc->firstChild->getName;

if ( $mtxtelm eq '' ) { 
	if ( $filetype eq 'TEI' ) {
		$mtxtelm = 'text'; 
		if ( $exclude eq '' ) { $exclude = "note|desc|gap|pb|fw|app"; };
	} elsif ( $filetype eq 'HTML' || $filetype eq 'html' ) { 
		$mtxtelm = 'body'; 
	} else {
		print "Please provide an node name within which tokenization should occur"; exit;
	};
};

if ( $rawxml =~ /<\/s>/ && $sentsplit ) {
	print "Already split into sentences - not splitting";
	$sentsplit = 0;
};
if ( $filetype ne 'TEI' && $sentsplit ) {
	print "Sentence splitting only supported in TEI";
	$sentsplit = 0;
};

# Check if not already tokenized
if ( $rawxml =~ /<\/tok>/ ) {
	if ( $force ) {
		# Forcing, so just go on
	} elsif ( $sentsplit ) {
		$sentsplit = 2;
	} else {
		print "Already tokenized"; exit;
	};
};

# We cannot have an XML tag span a line, so join them back on a single line
$rawxwl =~ s/<([^>]+)[\n\r]([^>]+)>/<\1 \2>/g;


# Take off the header and footer (ignore everything outside of $mtxtelm)
if ( $rawxml =~ /(<$mtxtelm>|<$mtxtelm [^>]*>).*?<\/$mtxtelm>/gsmi ) { $tagtxt = $&; $head = $`; $foot = $'; }
else { print "No element <$mtxtelm>"; exit; };

# There are some element that should never be inside a word - such as paragraphs. So add whitespace inside those to prevent errors
$tagtxt =~ s/(<\/(p|div)>)(<(p|div))(?=[ >])/\1\n\3/g;

# Deal with |~ encode line endings (from with page-by-page files)
$tagtxt =~ s/\s*\|~\s*((<[pl]b[^>]*>\s*?)*)\s*/\1/gsmi;

# Do some preprocessing
# decode will mess up encoded <> so htmlencode them
$tagtxt =~ s/&amp;/xxAMPxx/g;
$tagtxt =~ s/&lt;/xxLTxx/g;
$tagtxt =~ s/&gt;/xxGTxx/g;
$tagtxt = decode_entities($tagtxt);
# Protect HTML Entities so that they do not get split
# TODO: This should not exist anymore, right?
#$tagtxt =~ s/(&[^ \n\r&]+;)/xx\1xx/g;
#$tagtxt =~ s/&(?![^ \n\r&;]+;)/xx&amp;xx/g;

# <note> elements should not get tokenized
# And neither should <desc> or <gap>
# Take them out and put them back later
# TODO: this goes wrong with nested notes (which apt. are allowed in TEI)
$notecnt = 0;
while ( $tagtxt =~ /<($exclude)[^>]*(?<!\/)>.*?<\/\1>/gsmi )  {
	$notetxt = $&; $leftc = $`;
	$notes[$notecnt] = $notetxt; $newtxt = substr($leftc, -50).'#'.$notetxt;
	if ( $oldtxt eq $newtxt ) { 
		if ( $lc++ > 5 ) {
			print "Oops - trying to remove notes but getting into an infinite loop (or at least seemingly so).";
			print "before: $oldtxt"; 
			print "now: $newtxt"; 
			exit; 
		};
	};
	$oldtxt = $newtxt;
	$tagtxt =~ s/\Q$notetxt\E/<ntn n="$notecnt"\/>/;
	$notecnt++;
};	

# We need to remove linebreaks in the middle of a tag
$tagtxt =~ s/<([^>\n\r]*)[\n\r]+\s*/<\1 /g;

if ( $debug ) {
	print "\n\n----------------\nBEFORE TOKENIZING\n----------------\n$tagtxt----------------\n";
};

# Now actually tokenize
# Go line by line to make it faster
if ( $sentsplit != 2 ) {
	foreach $line ( split ( "\n", $tagtxt ) ) {

		# Protect XML tags
		$line =~ s/<([a-zA-Z0-9]+)>/<\1%%>/g;
		while ( $line =~ /<([^>]+) +/ ) {
			$line =~ s/<([^>]+) +/<\1%%/g;
		};
	
		# Protect MWE and other space-crossing or punctuation-including toks
		# When there is a parameter folder with a ptok.txt file
		if ( $params && -e "$params/ptoks.txt" ) {
		};
	
		$line =~ s/^(\s*)//; $pre = $1;
		$line =~ s/(\s*)$//; $post = $1;
	
		# Put tokens around all whitespaces
		if ( $line ne '' ) { $line = '<tokk>'.$line.'</tok>'; };

		$line =~ s/(\s+)/<\/tok>\1<tokk>/g;

		# <split/> being a non-TEI indication to split - should lead to two tokens
		$line =~ s/<split\/>/<\/tok><c form=" "><split\/><\/c><tokk>/g;

		# Remove toks around only XML tags
		$line =~ s/<tokk>((<[^>]+>)+)<\/tok>/\1/g;

		$line =~ s/%%/ /g;

		# Move tags between punctuation and </tok> out 
		$line =~ s/(\p{isPunct})(<[^>]+>)<\/tok>/\1<\/tok>\2/g;
		# Move tags between <tok> and punctuation out 
		$line =~ s/<tokk>(<[^>]+>)(\p{isPunct})/\1<tokk>\2/g;

		if ( $debug ) {
			print "BP|| $line\n";
		};

		# Split off the punctuation marks
		while ( $line =~ /(?<!<tokk>)(\p{isPunct}<\/tok>)/ ) {
			$line =~ s/(?<!<tokk>)(\p{isPunct}<\/tok>)/<\/tok><tokk>\1/g;
		};
		while ( $line =~ /(<tokk[^>]*>)(\p{isPunct})(?!<\/tok>)/ ) {
			$line =~ s/(<tokk[^>]*>)(\p{isPunct})(?!<\/tok>)/\1\2<\/tok><tokk>/g;
		};
		if ( $debug ) {
			print "IP|| $line\n";
		};

		# This should be repeated after punctuation
		# First remove empty <tok>
		$line =~ s/<tokk><\/tok>//g;
		$line =~ s/<tokk>(<[^>]+>)<\/tok>/\1/g;
		# Move beginning tags at the end out 
		$line =~ s/(<[^>\/ ]+ [^>\/]*>)<\/tok>/<\/tok>\1/g;
		if ( $debug ) {
			print "IP|| $line\n";
		};
		# Move end tags at the beginning out 
		$line =~ s/<tokk>(<\/[^>]+>)/\1<tokk>/g;

		# Move notes out 
		$line =~ s/<tokk>(<ntn [^>]+>)/\1<tokk>/g;
		$line =~ s/(<ntn [^>]+>)<\/tok>/<\/tok>\1/g;

		# Always move <p> out
		$line =~ s/<tokk>(<p [^>]+>)/\1<tokk>/g;
		$line =~ s/(<p [^>]+>)<\/tok>/<\/tok>\1/g;

		if ( $debug ) {
			print "AP|| $line\n";
		};
	
		#print $line; 
	
	
		# Go through all the tokens
		while ( $line =~ /<tokk>(.*?)<\/tok>/ ) {
			$a = ""; $b = ""; undef(%added);
			$m = $1; $n = $&;

			if ( $debug ) {
				print "TOK | $m";
			};
		
			# Check whether <tok> is valid XML
			( $chtok = $n ) =~ s/tokk/tok/g;
			$parser = XML::LibXML->new(); $tokxml = "";
			eval { $tokxml = $parser->load_xml(string => $chtok); };
		
			# Correct unmatched tags
			$chkcnt = 0;
			while ( !$tokxml && ( $m =~ /^<([^>]+)>/ || $m =~ /<([^>]+)>$/) ) { 
				if ( $chkcnt++ > 15 )  { print "Oops - infinite loop on $chtok"; exit; };
				if ( $m =~ /^<([^>]+)\/>/ ) {
					# Leftmost empty
					$a .= $&;
					$m = $';
				} elsif ( $m =~ /<([^>]+)\/>$/ ) {
					# Rightmost empty
					$b = $&.$b;
					$m = $`;
				} elsif ( $m =~ /^<\/([^>]+)>/ ) {
					# Leftmost closing
					$a .= $&;
					$m = $';
				} elsif ( $m =~ /<[^\/>][^>]*>$/ ) {
					# Rightmost opening
					$b .= $&.$b;
					$m = $`;
				} elsif ( $m =~ /^<([^\/>][^>]*)>/ ) {
					# Leftmost opening without close
					# TODO: This is not a complete check
					$tm = $&; $ti = $1; $rc = $';
					( $tn = $ti ) =~ s/ .*//; $tn =~ s/^\///; # tag name
					if ( $rc !~ /^((?<!<$tn ).)+<\/$tn>/ ) { 
						# Move out
						$m =~ s/^\Q$tm\E//;
						$a .= $tm;
					} else {
						# Mark as non-movable
						$m = "#".$m;
					};
				} elsif ( $m =~ /<\/([^>]+)>$/ ) {
					# Rightmost closing without open
					# TODO: This is not a complete check
					$tm = $&; $ti = $1; $lc = $`;
					( $tn = $ti ) =~ s/ .*//; $tn =~ s/^\///; # tag name
					( $tv = $ti ) =~ s/^[^ ]+ //;
					if ( $lc !~ /<$tn [^>\/]*>(.(?!<\/$tn>))+$/ ) { 
						# Move out
						$m =~ s/\Q$tm\E$//;
						$b = $tm.$b;
					} else {
						# Mark as non-movable
						$m = $m."#";
					};
				};
				if ( $debug ) {
					print "CTK1 | ($a) $m ($b)";
				};
				# Check whether <tok> is valid XML
				$parser = XML::LibXML->new(); $tokxml = "";
				eval { $tokxml = $parser->load_xml(string => "<tok>$m</tok>"); };
				$chcnt++;
			};
			$m =~ s/^#|#$//g;
		
			# If there are unmatched tags in the middle...
			if ( !$tokxml ) {
			
				# Count all the tags
				undef(%tgchk); # Clean count hash first
				while ( $m =~ /<([^ >]+)([^>]*)>/g ) {
					$tn = $1; $ta = $2;
					if ( $tn =~ /^\// ) {
						$tn = $';
						if ( $tgchk{$tn} > 0 ) {
							$tgchk{$tn}--;
						} else {
							# Closing before opening
							$a .= "<\/$tn>";
							$m = "<$tn rpt=\"1\">".$m;
						};
					} elsif ( $ta =~ /\/$/ || $tn =~ /\/$/ ) {
						# Ignore
					} else {
						$tgchk{$tn}++;
					};										
				}; 
				
				# Repair unpaired tags
				while ( ( $tn, $val ) = each ( %tgchk ) ) {
					# TODO: these should be added in the right order...
					$onto = "";
					if ( $val < 0 ) {
						for ( $i=0; $i>$val; $i-- ) {
							$a .= "<\/$tn>";
							$m = "<$tn rpt=\"1\">".$m;
							if ( $debug ) {
								print "CTK2 | ($a) $m+$onto ($b)";
							};
						};
					} elsif ( $val > 0  ) {
						for ( $i=0; $i<$val; $i++ ) {
							$onto = "<\/$tn>".$onto;
							$b .= "<$tn rpt=\"1\">";
							if ( $debug ) {
								print "CTK2 | ($a) $m+$onto ($b)";
							};
						};
					};
				};
				$m = $m.$onto;
				
				# Check whether <tok> is valid XML
				$parser = XML::LibXML->new(); $tokxml = "";
				eval { $tokxml = $parser->load_xml(string => "<tok>$m</tok>"); };
			};

		
			# Finally, look at the @form and @fform and @nform
			$fts = "";
			if ( $m =~ /^(.+)\|=([^<>]+)$/ ) { # echa|=hecha -> normalization
				$m = $1; $fts .= " nform=\"$2\"";
			};
			if ( $m =~ /^(.+)\|\|([^<>]+)$/ ) { # q||que -> expansion
				$m = $1; $fts .= " fform=\"$2\"";
			};
			if ( $m =~ /<[^>]+>/ ) {
				$frm = $m; $ffrm = "";
				$frm =~ s/<del.*?<\/del>//g; # Delete deleted texts
				$frm =~ s/-<lb[^>]*\/>//g; # Delete hyphens before word-internal hyphens
				if ( $frm eq "" ) { $frm = "--"; };
			
				# Deal with expansions
				if ( $frm =~ /<ex/ || $frm =~ /<am/ ) {
					if ( $frm =~ /<\/ex>/ ) { 
						$frm =~ s/<\/?expan [^>]*>//g; 
					}; # With <ex> - <expan> is no longer an expanded stretch
					$ffrm = $frm;
					$frm =~ s/<ex.*?<\/ex[^>]*>//g; # Delete expansions in form
					$ffrm =~ s/<am.*?<\/am[^>]*>//g; # Delete abrrev markers in fform
				};

				# Remove all (other) tags from @form
				$frm =~ s/<[^>]+>//g;
				$frm =~ s/"/&quot;/g;
				$ffrm =~ s/<[^>]+>//g;
				$ffrm =~ s/"/&quot;/g;
				# These appear if there are &gt; in the original
				$frm =~ s/>/&gt;/g;
				$frm =~ s/</&lt;/g;
				$ffrm =~ s/>/&gt;/g;
				$ffrm =~ s/</&lt;/g;

				if ( $m ne $frm ) { $fts .= " form=\"$frm\""; };
				if ( $ffrm ne '' && $frm ne $ffrm ) { $fts .= " fform=\"$ffrm\""; };
			};

			# Move <lb/> out from beginning of <tok> - should be redundant
			if ( $m =~ /^<lb[^>]*\/>/ ) {
				$m = $'; $a .= $&;
			};

			if ( $debug ) {
				$mo = "";  
				if ( $a ne ""  ) { $mo1 = "($a)"; };
				if ( $b ne "" ) { $mo2 = "($b)"; };
				print "TKK | $mo1 $m $mo2";
			};

			$line =~ s/\Q$n\E/$a<tok$fts>$m<\/tok>$b/;

		};

		# Move tags at the rim out of the tok
		$line =~ s/(<tok[^>]*>)(<([a-z0-9]+) [^>]*>)((.(?!<\/\3>))*.)<\/\3><\/tok>/\2\1\4<\/tok><\/\3>/gi;
		# This has to be done multiple time in principle since there might be multiple
		$line =~ s/(<tok[^>]*>)(<([a-z0-9]+) [^>]*>)((.(?!<\/\3>))*.)<\/\3><\/tok>/\2\1\4<\/tok><\/\3>/gi;

		# Split off the punctuation marks again (in case we moved out end tags)
		while ( $line =~ /(?<!<tok>)(\p{isPunct}<\/tok>)/ ) {
			$line =~ s/(?<!<tok>)(\p{isPunct}<\/tok>)/<\/tok><tok>\1/g;
		};
		while ( $line =~ /(<tok[^>]*>)(\p{isPunct})(?!<\/tok>)/ ) {
			$line =~ s/(<tok[^>]*>)(\p{isPunct})(?!<\/tok>)/\1\2<\/tok><tok>/g;
		};

		# Unprotect all MWE and other space-crossing or punctuation-including tokens
		while ( $line =~ /x#\{x[^\}]*%/ ) {
			$line =~ s/(x#\{x[^\}]*)%/\1 /g;
		};
		$line =~ s/x#\{x//g; $line =~ s/x\}#x//g;

		if ( $debug ) {
			print "LE|| $line\n";
		};
		
		$teitext .= $pre.$line.$post."\n";
	};

	# Join some non-splittable sequences		
	$teitext =~ s/<tok>\[<\/tok><tok>\.<\/tok><tok>\.<\/tok><tok>\.<\/tok><tok>\]<\/tok>/<tok>[...]<\/tok>/g; # They can also be inside a tok
	$teitext =~ s/<tok>\(<\/tok><tok>\.<\/tok><tok>\.<\/tok><tok>\.<\/tok><tok>\)<\/tok>/<tok>(...)<\/tok>/g; # They can also be inside a tok
	$teitext =~ s/<tok>\.<\/tok><tok>\.<\/tok><tok>\.<\/tok>/<tok>...<\/tok>/g; # They can also be inside a tok

	$teitext =~ s/xx(&(?!xx)[^ \n\r&]+;)xx/\1/g; # Unprotect HTML Characters
	$teitext =~ s/xxAMPxx/&amp;/g; # Undo xxAMPxx
	$teitext =~ s/xxLTxx/&lt;/g; # Undo xxAMPxx
	$teitext =~ s/xxGTxx/&gt;/g; # Undo xxAMPxx

	# A single capital with a dot is likely a name
	$teitext =~ s/<tok>([A-Z])<\/tok><tok>\.<\/tok>/<tok>\1.<\/tok>/g; # They can also be inside a tok

} else {
	$teitext = $tagtxt;
}; 
 
if ( $sentsplit ) {
	# Now - split into sentences; 
	
	# Start by making a <s> inside each <p> or <head>, fallback to <div>, or else just the outer xml (<text>) 
	if ( $teitext =~ /<\/(p|head)>/ ) {
		$teitext =~ s/(<p(?=[ >])[^>]*>)/\1<s>/g;
		$teitext =~ s/(<\/p>)/<\/s>\1/g;
		$teitext =~ s/(<head(?=[ >])[^>]*>)/\1<s>/g;
		$teitext =~ s/(<\/head>)/<\/s>\1/g;
	} elsif ( $teitext =~ /<\/div>/ ) {
		$teitext =~ s/(<div(?=[ >])[^>]*>)/\1<s>/g;
		$teitext =~ s/(<\/div>)/<\/s>\1/g;
	} else {
		# Add a sentence start at the beginning of the mtxt
		$teitext =~ s/^(<[^>]+>)/\1<s>/;
		$teitext =~ s/(<\/[^>]+>)$/<\/s>\1/;
	};

	# Put the notes back
	while ( $teitext =~ /<ntn n="(\d+)"\/>/ ) {
		$notenr = $1; $notetxt = $notes[$notenr]; 
		$notecode = $&;
		$teitext =~ s/\Q$notecode\E/$notetxt/;
	};
	
	$presplit = $teitext; 
	
	# Now - add </s><s> after every sentence-final token
	# TODO: this should be done one at a time to fallback only where needed
	$teitext =~ s/(<tok [^>]+>[.?!]<\/tok>)(\s*)/\1<\/s>\2<s>/g; 
	
	# In case the splitting messed up the XML, undo
	$parser = XML::LibXML->new(); $tmp = "";
	eval {
		$tmp = $parser->load_xml(string => $teitext);
	};
	if ( !$tmp ) {
		print "Splitting within paragraphs failed - reverting: $@";
		$teitext = $presplit; 
	};
	
	# Finally, remove empty sentences
	$teitext =~ s/<s><\/s>//g;
	
} else {

	# Put the notes back
	while ( $teitext =~ /<ntn n="(\d+)"\/>/ ) {
		$notenr = $1; $notetxt = $notes[$notenr]; 
		$notecode = $&;
		$teitext =~ s/\Q$notecode\E/$notetxt/;
	};

};


$xmlfile = $head.$teitext.$foot;


# Now - check if this turned into valid XML
$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(string => $xmlfile);
};
if ( !$doc ) { 
	print "XML got messed up - saved to /tmp/wrong.xml\n"; 
	open FILE, ">/tmp/wrong.xml";
	binmode ( FILE, ":utf8" );
	print FILE $xmlfile;
	close FILE;
	
	$err = `xmlwf /tmp/wrong.xml`;
	if ( $err =~ /^(.*?):(\d+):(\d+):/ ) {
		$line = $2; $char = $3;
		print "First XML Error: $err";
		print `cat /tmp/wrong.xml | head -n $line | tail -n 1`;
	};
	
	exit; 
};

if ( $toknode ne 'tok' || $enumerate ) {
	# Turn all tok into whatever we wanted them to be
	$tokcnt = 1; 
	foreach $tk ( $doc->findnodes("//$mtxtelm//tok") ) {
		if ( $toknode ne 'tok' ) { $tk->setName($toknode); };
		if ( $enumerate ) { $tk->setAttribute('id', 'w-'.$tokcnt++); };
	};
}; 

# Add a revisionDesc to indicate the file was tokenized (for TEI files)
if ( $filetype eq 'TEI' ) {
	$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"xmltokenize\"]");
	$when = strftime "%Y-%m-%d", localtime;
	$revnode->setAttribute("when", $when);
	if ( $sentsplit == 2 ) {
		$revnode->appendText("split into sentences using xmltokenize.pl");
	} elsif ( $sentsplit == 1 ) {
		$revnode->appendText("tokenized and split into sentences using xmltokenize.pl");
	} else {
		$revnode->appendText("tokenized using xmltokenize.pl");
	};
};


$xmlfile = $doc->toString;

# Turn namespace back on
$xmlfile =~ s/xmlnsoff=/xmlns=/;


if ( $test ) { 
	print  $xmlfile;
} else {

	open FILE, ">$filename";
	print FILE $xmlfile;
	close FILE;

	print "$filename has been tokenized";

};

sub makenode ( $xml, $xquery ) {
	my ( $xml, $xquery ) = @_;
	@tmp = $xml->findnodes($xquery); 
	if ( scalar @tmp ) { 
		$node = shift(@tmp);
		if ( $debug ) { print "Node exists: $xquery"; };
		return $node;
	} else {
		if ( $xquery =~ /^(.*)\/(.*?)$/ ) {
			my $parxp = $1; my $thisname = $2;
			my $parnode = makenode($xml, $parxp);
			$thisatts = "";
			if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
				$thisname = $1; $thisatts = $2;
			};
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
			
		} else {
			print "Failed to find or create node: $xquery";
		};
	};
};
