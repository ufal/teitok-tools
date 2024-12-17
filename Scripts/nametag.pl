use LWP::Simple;
use LWP::UserAgent;
use Getopt::Long;
use XML::LibXML;
use URI::Escape;
use JSON;
use POSIX qw(strftime);

# Script to run NameTag on a TEITOK/XML file
# NameTag (https://lindat.mff.cuni.cz/services/nametag/) is a NER tool

binmode(STDOUT, ":utf8");

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'verbose' => \$verbose, # debugging mode
            'test' => \$test, # tokenize to string, do not change the database
            'force' => \$force, # tokenize to string, do not change the database
            'noids' => \$noids, # do not place a @corresp on the names
            'model=s' => \$model, # language of input
            'lang=s' => \$lang, # language of input
            'langxp=s' => \$langxp, # language of input
            'filename=s' => \$filename, # language of input
            );

$\ = "\n"; $, = "\t";

if ( !$filename ) { $filename = shift; };

$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });

$parser = XML::LibXML->new(); $doc = "";
eval {
	$doc = $parser->load_xml(location => $filename );
};
if ( !$doc ) { print "Failed to load XML in $filename"; exit; };

if (  $doc->findnodes("//text//name") && !$force ) {
	print "Already named"; exit;
};

foreach $tok ( $doc->findnodes("//tok") ) {
	$toktxt = $tok->textContent;
	$tokid = $tok->getAttribute('id');
	if ( $toktxt ) { 
		$vert .= $toktxt."\n"; 
		$cnt++;
		$conllu .= $cnt."\t$toktxt\t_\t_\t_\t_\t_\t_\t_\t$tokid\n"; 
	};
};

%ntmodels = (
	"ces" => "czech-cnec2.0-200831",
	"nld" => "dutch-conll-200831",
	"eng" => "english-conll-200831",
	"spa" => "spanish-conll-200831",
	"deu" => "german-conll-200831",
);

if ( !$lang && $langxp ) { 
	$tmp = $doc->findnodes($langxp);
	if ( $tmp ) {
		$tmpnode = $tmp->item(0);
		if ( $tmpnode->nodeType == 2 ) {
			$lang = $tmpnode->value;
		} elsif ( $tmpnode->nodeType == 1 ) {
			$lang = $tmpnode->textContent;
		};
	};
};
if ( !$model && $lang ) { $model = $ntmodels{$lang}; };
if ( !$model ) { print "No model found - $model / $lang / $langxp"; exit; };

#$url = "http://lindat.mff.cuni.cz/services/nametag/api/recognize?output=xml&input=vertical&model=$model&data=".uri_escape_utf8($data);
if ( $debug ) { print $url; };

utf8::upgrade($data);

%form = (
	"data" => $conllu, ## "data" => $vert,
	"model" => $model,
	"input" => "conllu",
	"output" => "conllu-ne",
);

if ( $debug ) { print $data; };
$url = 'http://lindat.mff.cuni.cz/services/nametag/api/recognize';

if ( $debug || $verbose ) { print "Submitting $cnt tokens to $url / model $model"};

$res = $ua->post( $url, \%form );
$jsdat = $res->decoded_content;
eval {
	$jsonkont = decode_json($jsdat);
};
if ( !$jsonkont ) {
	print "Error: failed to get parsed result from server";
	print $res->message();
	exit;
};
# $jf = "<doc>".$jsonkont->{'result'}."</doc>";
$jf = $jsonkont->{'result'}; 
$jf =~ s/\\n/\n/g;
if ( $debug ) { print $jf; }; 
foreach $line ( split("\n", $jf) ) {
	@tmp = split("\t", $line);
	if ( $tmp[9] =~ /(.*?)\|(.*)/ ) { 
		$tokid = $1; $ners = $2;	
		foreach $ner ( split("-", $ners) ) {
			if ( $ner =~ /NE=(.*)_(\d+)/ ) {
				$type = $1; $nerid = $2;
				$nerlist{$nerid} .= "$tokid,";
				$nertype{$nerid} = $type;
			};
		}
	};
};
if ( !$jf ) {
	print "Unable to parse result";
	exit;
};


while ( ($nerid, $ids ) = each(%nerlist) ) {
	$type = $nertype{$nerid};
	$ids =~ s/,$//;
	@idlist = split(",", $ids);
	$t1 = $idlist[0]; $tx = $idlist[-1];
	if ( $debug ) { print $nerid, $ids, $type, "$t1 - $tx"; };
	$tmp = $doc->findnodes("//tok[\@id=\"$t1\"]");
	if ( $tmp ) {
		$tok1 = $tmp->item(0);
		$newne = $doc->createElement('name');
		$newne->setAttribute('type', $type);
		if ( !$noids ) { $newne->setAttribute('sameAs', "#".join(" #", @idlist)); };
		if ( $tok1 ) { 
			if ( $verbose ) {
				print " - adding NER $type on $ids ($nerid)";
			};
			$tok1->parentNode->insertBefore($newne, $tok1);

			while ( $sib = $newne->nextSibling() ) {
				$newne->addChild($sib);
				if ( $sib->nodeType == 1 && $sib->getAttribute('id') eq $tx ) { 
					last; 
				};
			};
			if( $debug ) { 	print $newne->toString(1); };
		} else {
			print "No parent node for $t1";
		};
	};
};

# Add a revisionDesc to indicate the file was tokenized
$revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"nametag\"]");
$when = strftime "%Y-%m-%d", localtime;
$revnode->setAttribute("when", $when);
$revnode->appendText("NER using NameTag model $model");

$xmlfile = $doc->toString;

if ( $test ) { 
	print  $xmlfile;
} else {

	# Make a backup of the file
	( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
	$date = strftime "%Y%m%d", localtime; 
	$buname =~ s/\.xml/-$date.nt.xml/;
	$cmd = "/bin/cp $filename $buname";
	`$cmd`;

	open FILE, ">$filename";
	print FILE $xmlfile;
	close FILE;

	( $renum = $scriptname ) =~ s/nametag/xmlrenumber/;

	print "$filename has been NERed";
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
	