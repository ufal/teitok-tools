use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);
use File::Find;
use LWP::Simple;
use LWP::UserAgent;
use JSON;
use XML::LibXML;
use Encode;

# Spellcheck tokenized TEITOK/XML file using Korektor
# Korektor (http://lindat.mff.cuni.cz/services/korektor) is a statistical spellchecker

$scriptname = $0;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'file=s' => \$filename, # which UDPIPE model to use
            'model=s' => \$model, # which UDPIPE model to use
            'folder=s' => \$folder, # Originals folder
            'token=s' => \$token, # token node
            'tokxp=s' => \$tokxp, # token XPath
            );

$\ = "\n"; $, = "\t";

$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
$parser = XML::LibXML->new(); 

if ( !$filename ) { $filename = shift; };
if ( !$token ) { $token = "tok"; };
if ( !$model ) { $model = "czech-spellchecker-130202"; };

binmode(STDOUT, ":utf8");

print "Using model: $model";


if ( $filename ) {
	if ( !-e $filename ) { print "No such file: $file"; exit; };
	treatfile($filename);
} elsif ( $folder ) { 
	if ( !-d $folder ) { print "No such folder: $folder"; exit; };
	find({ wanted => \&treatfile, follow => 1, no_chdir => 1 }, $folder);
} else {
	print "Please provide a file or folder to parse"; exit;
};


STDOUT->autoflush();

sub treatfile ( $fn ) {
	$tokcnt = 1;
	$fn = $_; if ( !$fn ) { $fn = @_[0]; }; $orgfile = $fn;
	if ( !-d $fn ) { 
		print "\nTreating $fn";
	
		# read the XML
		eval {
			$xml = $parser->load_xml(location => $fn, load_ext_dtd => 0);
		};
		if ( !$xml ) { 
			print "Invalid XML in $fn";
			continue;
		};
		if ( !$tokxp ) { $tokxp = "//$token"; };
		$num = 1; 

		$toklist = "";
		foreach $tok ( $xml->findnodes($tokxp) ) {
			if ( $newsent ) { $toklist .= "\n"; };
			$newsent = 0;
			$tokid = $tok->getAttribute('id');
			if ( !$tokid ) { $tokid = "w-".$tokcnt++; $tok->setAttribute('id', $tokid); };
			$form = $tok->getAttribute("form");
			if ( !$form ) { $form = $tok->textContent; };
			if ( !$form ) { $form = "_"; };	
			push(@tokarray, [$form, $tokid]);
			$tokhash{$tokid} = $tok;
			$toklist .= $form." ";
		};
		utf8::upgrade($toklist);
		
		if ( $debug ) { 
			binmode(STDOUT, ":utf8");
			print $toklist; 
		};
				
		$udfile = $fn;
		if ( $folder eq '' ) { $udfile = "udpipe/$udfile"; };
		$udfile =~ s/\..*?$/\.sug/;
		( $tmp = $udfile ) =~ s/\/[^\/]+$//;
		$response = runkorektor($toklist, $model);

		foreach $span ( @{$response} ) {
			@tmp = @{$span};
			$words = $tmp[0];
			utf8::upgrade($words);
			if ( scalar @tmp == 1 ) { 
				# A span of non-corrected words
				foreach $word ( split(" ", $words) ) {
					if ( $tokarray[0][0] eq $word ) { shift(@tokarray); } else { print "Oops: $word =/= ".$tokarray[0][0]; exit; };
				};
			} else {
				# A correction
				$corr = $tmp[1];
				if ( $tokarray[0][0] eq $words ) { 
					$todoid = $tokarray[0][1];
					shift(@tokarray); 
					$tokhash{$todoid}->setAttribute('nform', $corr);
					print "    - corrected $tokid from $words to $corr";
				} else { print "Oops: $words =/= ".$tokarray[0][0]; exit; };
			};
		};
		
		# Add the revision statement
		$revnode = makenode($xml, "/TEI/teiHeader/revisionDesc/change[\@who=\"korektor\"]");
		$when = strftime "%Y-%m-%d", localtime;
		$revnode->setAttribute("when", $when);
		$revnode->appendText("Spell-checked with Korektor using $model");
		
		$outfile = $orgfile;
		print "Writing parsed file to $outfile\n";
		open OUTFILE, ">$outfile";
		print OUTFILE $xml->toString;	
		close OUTFLE;
		
	};
};


sub runkorektor ( $raw, $model ) {
	($raw, $model) = @_;

	%form = (
		"input" => "horizontal",
		"model" => $model,
		"data" => $raw,
	);
	
	$url = "http://lindat.mff.cuni.cz/services/korektor/api/suggestions";
		print " - Running korektor from $url / $model";
	$res = $ua->post( $url, \%form );
	$jsdat = $res->decoded_content;
	$jsonkont = decode_json($res->decoded_content);

	return $jsonkont->{'result'};
	
};


sub textprotect ( $text ) {
	$text = @_[0];
	
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g; 
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&#039;/g;

	return $text;
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

