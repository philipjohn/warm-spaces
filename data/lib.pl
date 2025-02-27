#!/usr/bin/perl

use utf8;
use JSON::XS;
use Encode;
binmode STDOUT, 'utf8';
binmode STDERR, 'utf8';

my %colours = (
	'black'=>"\033[0;30m",
	'red'=>"\033[0;31m",
	'green'=>"\033[0;32m",
	'yellow'=>"\033[0;33m",
	'blue'=>"\033[0;34m",
	'magenta'=>"\033[0;35m",
	'cyan'=>"\033[0;36m",
	'white'=>"\033[0;37m",
	'none'=>"\033[0m"
);

sub msg {
	my $str = $_[0];
	my $dest = $_[1]||STDOUT;
	foreach my $c (keys(%colours)){ $str =~ s/\< ?$c ?\>/$colours{$c}/g; }
	print $dest $str;
}

sub error {
	my $str = $_[0];
	$str =~ s/(^[\t\s]*)/$1<red>ERROR:<none> /;
	msg($str,STDERR);
}

sub warning {
	my $str = $_[0];
	$str =~ s/(^[\t\s]*)/$1$colours{'yellow'}WARNING:$colours{'none'} /;
	print STDERR $str;
}
sub parseText {
	my $str = $_[0];
	$str =~ s/<br ?\/?>/ /g;
	$str =~ s/<[^\>]+>//g;
	$str =~ s/(^[\s]+|[\s]+$)//g;
	$str =~ s/\&nbsp\;/ /g;
	$str =~ s/\&#8211;/-/g;
	$str =~ s/\&#039;/\'/g;
	$str =~ s/\x{a0}/ /g;
	$str =~ s/Â//g;
	return $str;
}
sub trimText {
	my $str = $_[0];
	$str =~ s/(^[\s]+|[\s]+$)//g;
	return $str;
}
sub getURL {
	my $url = $_[0];
	return @lines = `wget -q -e robots=off  --no-check-certificate -O- "$url"`;
}

sub getDataFromURL {
	my $d = shift;
	my $n = shift;
	my ($url,$file,$age,$now,$epoch_timestamp,$header,$h);

	$url = $d->{'data'}[$n]{'url'};

	$file = $rawdir.$d->{'id'}.($n ? "-$n":"").".".$d->{'data'}[$n]{'type'};
	$age = 100000;
	if(-e $file){
		$epoch_timestamp = (stat($file))[9];
		$now = time;
		$age = ($now-$epoch_timestamp);
	}

	msg("\tFile: $file\n");
	if($age >= 86400 || -s $file == 0){
		#`wget -q -e robots=off  --no-check-certificate -O $file "$url"`;
		$header = "";
		if($d->{'data'}[$n]{'headers'}){
			foreach $h (keys(%{$d->{'data'}[$n]{'headers'}})){
				$header .= ($header ? " " : "")."-H \"$h: $d->{'data'}[$n]{'headers'}{$h}\"";
			}
		}		
		`curl -s -L $header --compressed -o $file "$url"`;
		msg("\tDownloaded\n");
	}
	return $file;
}

sub getURLToFile {
	my $url = $_[0];
	my $file = $_[1];
	my $attempt = $_[2]||1;
	my ($age,$now,$epoch_timestamp,$delay,$n);

	$age = 100000;
	if(-e $file){
		$epoch_timestamp = (stat($file))[9];
		$now = time;
		$age = ($now-$epoch_timestamp);
	}
	# If the previous download involved more than one attempt we will add a delay here
	if($attempt > 1){
		msg("\tAdding a wait of 30 seconds\n");
		sleep 30;
	}

	if($age >= 86400 || -s $file == 0){
		$n = 1;
		msg("\tDownloading $url\n");
		`wget -q --no-check-certificate -O $file "$url"`;

		if(-s $file == 0){
			$n = 2;
			sleep 10;
			msg("\tDownload 2nd attempt from $url\n");
			`wget -q --no-check-certificate -O $file "$url"`;

			if(-s $file == 0){
				$n = 3;
				sleep 30;
				msg("\tDownload 3rd attempt from $url\n");
				`wget -q --no-check-certificate -O $file "$url"`;

				if(-s $file == 0){
					$n = 4;
					sleep 60;
					msg("\tDownload 4th attempt from $url\n");
					`wget -q --no-check-certificate -O $file "$url"`;
				}
			}
		}
	}
	
	return $n;
}
sub makeDir {
	my $str = $_[0];
	my @bits = split(/\//,$str);
	my $tdir = "";
	my $i;
	for($i = 0; $i < @bits; $i++){
		$tdir .= $bits[$i]."/";
		if(!-d $tdir){
			`mkdir $tdir`;
		}
	}
}
sub getFileContents {
	my (@files,$str,@lines,$i);
	my $file = $_[0];
	open(FILE,"<:utf8",$file);
	@lines = <FILE>;
	close(FILE);
	return @lines;
}
sub getJSON {
	my (@files,$str,@lines);
	my $file = $_[0];
	open(FILE,"<:utf8",$file);
	@lines = <FILE>;
	close(FILE);
	$str = (join("",@lines));
	if(!$str){ $str = "{}"; }
	return JSON::XS->new->decode($str);	
}

sub tidyJSON {
	my $json = shift;
	my $depth = shift;
	my $d = $depth+1;

	$txt = JSON::XS->new->canonical(1)->pretty->space_before(0)->encode($json);
	$txt =~ s/   /\t/g;
	$txt =~ s/([\{\,\"])\n\t{$d,}([\"\}])/$1 $2/g;
	$txt =~ s/"\n\t{$depth,}\}/\" \}/g;
	$txt =~ s/null\n\t{$depth,}\}/null \}/g;

	# Kludge to fix validation white space issues with warm_spaces entries
	while($txt =~ s/("description": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("address": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("title": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("url": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("accessibility": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("_text": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	while($txt =~ s/("contact": "[^\"]*)[	]([^\"]*")/$1 $2/g){}
	$txt =~ s/\"\*\*/\"/g;
	$txt =~ s/  \"/\"/g;
	$txt =~ s/	 / /g;
	$txt =~ s/ / /g;
	$txt =~ s/ {2,}/ /g;

	return $txt;
}

sub makeJSON {
	my $json = shift;
	my $compact = shift;
	
	if($compact){
		$txt = JSON::XS->new->canonical(1)->encode($json);
	}else{
		$txt = JSON::XS->new->canonical(1)->pretty->space_before(0)->encode($json);
		
		$txt =~ s/   /\t/g;

		$txt =~ s/(\t{3}.*)\n/$1/g;
		$txt =~ s/\,\t{3}/\, /g;
		$txt =~ s/\t{2}\}(\,?)\n/ \}$1\n/g;
		$txt =~ s/\{\n\t{3}/\{ /g;
		$txt =~ s/\{\t+\"/\{ \"/g;
		$txt =~ s/\"\t+\}/\" \}/g;

		
		$txt =~ s/\}\,\n\t\{/\},\{/g;
		$txt =~ s/",[\s\t]+"/", "/g;
	}	
	return $txt;
}

# Attempt to parse free-text dates/times into the OSM format https://wiki.openstreetmap.org/wiki/Key:opening_hours
sub parseOpeningHours {
	my $hours = shift;
	my (@days,$parsed,$str,$i,$j,$d,$day1,$day2,$t1,$t2,$ok,$t,$mod1,$mod2,$nstr,$nth);

	@days = (
		{'match'=>['Monday','Mon'],'short'=> 'Mo','key'=>'monday'},
		{'match'=>['Tuesday','Tue','Tues'],'short' => 'Tu','key'=>'tuesday'},
		{'match'=>['Wednesday','Wed'],'short' => 'We','key'=>'wednesday'},
		{'match'=>['Thursday','Thurs','Thur','Thu'],'short' => 'Th','key'=>'thursday'},
		{'match'=>['Friday','Fri'],'short' => 'Fr','key'=>'friday'},
		{'match'=>['Saturday','Sat'],'short' => 'Sa','key'=>'saturday'},
		{'match'=>['Sunday','Sun'],'short' => 'Su','key'=>'sunday'}
	);
	
	# Tidy up any existing times and build parsed string
	$parsed = "";
	for($i = 0; $i < @days; $i++){
		if($hours->{$days[$i]->{'key'}}){
			$hours->{$days[$i]->{'key'}} =~ s/^[\s\t]+\-[\s\t]+\/[\s\t]+\-[\s\t]+$//g;
			$hours->{$days[$i]->{'key'}} =~ s/[\s\t]+\/[\s\t]+\-[\s\t]+$//g;
			$hours->{$days[$i]->{'key'}} =~ s/^[\s\t]+\-[\s\t]+\/[\s\t]+//g;
			if($hours->{$days[$i]->{'key'}} =~ /[0-9]/){
				$parsed .= ($parsed ? ", ":"").ucfirst($days[$i]->{'key'}).": ".$hours->{$days[$i]->{'key'}};
			}
			delete $hours->{$days[$i]->{'key'}};
		}
	}
	if($parsed && !$hours->{'_text'}){
		$hours->{'_text'} = $parsed;
	}

	$str = "".($hours->{'_text'}||"");
	
	if($str && !$hours->{'_parsed'}){

		$str =~ s/\: - \/ /\: /g;	# Fix empty dates in some formats
		$str =~ s/ at [^0-9]+ from /: /g;
		$str =~ s/ (to|until|til) / - /g;
		$str =~ s/ from /: /g;
		$str =~ s/ (\&|and) /, /g;
		$str =~ s/\&apos\;//g;
		$str =~ s/([^0-9]) \&amp\; ([^0-9])/$1, $2/g;
		$str =~ s/ (mornings?|afternoons?)/ /g;
		$str =~ s/ ?\([^\)]+\)//g;
		$str =~ s/\//, /g;
		$str =~ s/[—–]/-/g;
		$str =~ s/24 hours/00:00-24:00/g;
		$str =~ s/ (am|pm) /$1/g;	# trim spaces before am/pm

		# Convert "weekdays" or "weekends" into day ranges
		$str =~ s/Weekdays/Mo-Fr/gi;
		$str =~ s/Weekends/Sa-Su/gi;
		$str =~ s/(everyday|Every day|7 days a week|7 days|daily)/Mo-Su/gi;

		# Convert "noon" values to numbers
		$str =~ s/12 ?noon/12:00/gi;
		$str =~ s/noon/ 12:00/gi;

		# Standardise A.M./P.M./a.m./p.m./AM/PM into am/pm
		$str =~ s/a\.?m\.?/am/gi;
		$str =~ s/p\.?m\.?/pm/gi;

		for($i = 0; $i < @days; $i++){
			for($j = 0; $j < @{$days[$i]->{'match'}}; $j++){
				$d = $days[$i]->{'match'}[$j];
			
				# Replace any string that refers to e.g. "first Sunday" with "Su[1]"
				while($str =~ /((1st|first|First|2nd|second|Second|3rd|third|Third|4th|fourth|Fourth|last|Last|and|\,|\s)+) $d( of (the|each|every) month)?\,?/){
					$nth = $1;
					$nstr = "";
					if($nth =~ /(first|1st)/i){ $nstr .= ($nstr?",":"")."1"; }
					if($nth =~ /(second|2nd)/i){ $nstr .= ($nstr?",":"")."2"; }
					if($nth =~ /(third|3rd)/i){ $nstr .= ($nstr?",":"")."3"; }
					if($nth =~ /(fourth|4th)/i){ $nstr .= ($nstr?",":"")."4"; }
					if($nth =~ /last/i){ $nstr .= ($nstr?",":"")."-1"; }
					if($nstr){ $nstr = " $days[$i]->{'short'}\[$nstr\]"; }
					else { $nstr = " ".$d; }
					$str =~ s/((1st|first|First|2nd|second|Second|3rd|third|Third|4th|fourth|Fourth|last|Last|and|\,|\s)+) $d( of (the|each|every) month)?\,?/$nstr/;
				}				

				# Replace a day match with the short version
				$str =~ s/$d[\'s]*(\W|$)/$days[$i]->{'short'}$1/gi;
			}
		}

		# Match day range + time
		while($str =~ s/(Mo|Tu|We|Th|Fr|Sa|Su)(\[[0-9\,\-]\])?[\s\t]*[\-\–][\s\t]*(Mo|Tu|We|Th|Fr|Sa|Su)(\[[0-9\,]\])?[\;\:\,]?[\s\t]*([0-9\:\.\,apm\s\t\-]+)//){
			$day1 = $1;
			$mod1 = $2;
			$day2 = $3;
			$mod2 = $4;
			$t = getHourRange($5);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1-$day2$mod2 $t";
			}
		}

		# Match time + day range
		while($str =~ s/([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)[\s\:\,]*(Mo|Tu|We|Th|Fr|Sa|Su)(\[[0-9\,\-]\])?[\s\t]*[\-\–][\s\t]*(Mo|Tu|We|Th|Fr|Sa|Su)(\[[0-9\,\-]\])?//){
			$day1 = $4;
			$mod1 = $5;
			$day2 = $6;
			$mod2 = $7;
			$t = getHourRange($1);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1-$day2$mod2 $t";
			}
		}

		# Match multiple days with time
		while($str =~ s/(((Mo|Tu|We|Th|Fr|Sa|Su)\,? ?){2,})[\s\t]*[\-\:]*[\s\t]*([0-9\:\.\,amp\s\t\-]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,amp\s\t\-]+(am|pm)?)//){
			$day1 = $1;
			$t = getHourRange($4);
			if($t){
				for($i = 0; $i < @days; $i++){
					if($day1 =~ $days[$i]->{'short'}){
						$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$days[$i]->{'short'} $t";
					}
				}
			}
		}

		# Match single day + time
		while($str =~ s/(Mo|Tu|We|Th|Fr|Sa|Su)(\[[0-9\,\-]+\])?[\s\t]*[\;\:\,\-]?[\s\t]*([0-9\:\.\,amp\s\t\-]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)//){
			$day1 = $1;
			$mod1 = $2;
			$t = getHourRange($3);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1 $t";
			}
		}

		# Match time + "every" + single day
		while($str =~ s/([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)[\,]? every *(\[[0-9\,\-]\])? *(Mo|Tu|We|Th|Fr|Sa|Su)//){
			$day1 = $3;
			$mod1 = $2;
			$t = getHourRange($1);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1 $t";
			}
		}
		
		# Match time + "on" + single day
		while($str =~ s/([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)[\,]? on *(Mo|Tu|We|Th|Fr|Sa|Su)//){
			$day1 = $4;
			$t = getHourRange($1);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1 $t";
			}
		}
		
		# Match time + single day
		while($str =~ s/([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?) *(Mo|Tu|We|Th|Fr|Sa|Su)//){
			$day1 = $4;
			$t = getHourRange($1);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1 $t";
			}
		}

		# Match "Daily"
		while($str =~ s/(Daily|7 days (a|per) week)(\[[0-9\,\-]\])?[\;\:\,]?[\s\t]*([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)//i){
			$day1 = "Mo-Su";
			$mod1 = $2;
			$t = getHourRange($3);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1 $t";
			}
		}

		# Match "Daily"
		while($str =~ s/([0-9\:\.\,]+(am|pm)?[\s\t]*[\-\–][\s\t]*[0-9\:\.\,]+(am|pm)?)[\s\t\,]*(Daily|7 days (a|per) week)//i){
			$day1 = "Mo-Su";
			$t = getHourRange($1);
			if($t){
				$hours->{'_parsed'} .= ($hours->{'_parsed'} ? "; ":"")."$day1$mod1 $t";
			}
		}

		if(!$hours->{'_parsed'}){
			warning("\tCan't parse hours from \"$hours->{'_text'}\"\n");
		}
	}
	
	# Now delete individual days but add them to a '_text' string
	if(!$hours->{'_text'}){
		$hours->{'_text'} = "";
		for($i = 0; $i < @days; $i++){
			$hours->{$days[$i]{'key'}} =~ s/(\-[\s\t]*\/[\s\t]*\-)//g;
			$hours->{$days[$i]{'key'}} =~ s/(^[\s\t]+|[\s\t]+$)//g;
			if(!($hours->{$days[$i]{'key'}} eq "-" || $hours->{$days[$i]{'key'}} eq "")){
				$hours->{'_text'} .= ($hours->{'_text'} ? "; ":"").$days[$i]{'key'}.": ".$hours->{$days[$i]{'key'}};
			}
			delete $hours->{$days[$i]{'key'}};
		}
	}

	$hours->{'opening'} = $hours->{'_parsed'};
	delete $hours->{'_parsed'};
	if($hours->{'opening'}){
		# Correction - not sure why there are commas between date/times
		$hours->{'opening'} =~ s/\, /\; /g;
	}
	return $hours;
}

sub getHourRange {
	my $str = $_[0];
	my ($t1,$t2,@times,$t,$out);
	@times = split(/\,/,$str);
	$out = "";
	for($t = 0; $t < @times; $t++){
		($t1,$t2) = split(/ ?[\-\–] ?/,$times[$t]);
		if($t1 !~ /[0-9]/ && $t2 !~ /[0-9]/){
			# No valid looking times so don't add anything
		}else{
			if($t1 !~ /(am|pm)/ && $t2 =~ /(pm)/ && $t1 < 12 && $t2 < 12 && $t1 < $t2){ $t1 += 12; }
			$out .= ($out?",":"").niceHours($t1)."-".niceHours($t2);
		}
	}
	return $out;
}

sub niceHours {
	my $str = $_[0];
	my ($am,$pm,$hh,$mm);
	$am = 0;
	$pm = 0;
	if($str =~ s/am//g){ $am = 1; }
	if($str =~ s/pm//g){ $pm = 1; }
	$str =~ s/Closed//ig;	# Fudge for LCC times

	if($str =~ /[\:\.]/){
		($hh,$mm) = split(/[\:\.]/,$str);
		$mm = substr($mm,0,2);	# Truncate to two digits (sometimes people mistype an extra digit)
	}else{
		$hh = $str+0;
		$mm = 0;
	}
	if($pm){
		$hh += 12;
		# Correction for people using 12:30pm to mean afternoon
		if($hh >= 24){ $hh -= 12; }
	}
	if($hh > 24){ $hh /= 100; }
	return sprintf("%02d:%02d",$hh,$mm);
}

my %postcodes;
my %postcodelookup;

sub getPostcode {
	my $postcode = $_[0];
	my ($i,@lines,$pc);
	
	$postcode =~ /^([A-Z]{1,2})/;
	$pc = $1;
	$postcode =~ s/ //g;
	
	if(!$postcodes{$pc}){
	
		@lines = getURL("https://odileeds.github.io/Postcodes2LatLon/postcodes/".$pc.".csv");
		msg("\tDownloaded postcodes for $pc.\n");
		$postcodes{$pc} = 1;

		if(@lines > 1){
			for($i = 1; $i < @lines; $i++){
				$lines[$i] =~ s/[\n\r]//g;
				($p,$lat,$lon) = split(/,/,$lines[$i]);
				$p =~ s/ //g;
				$postcodelookup{$p} = {'lat'=>$lat,'lon'=>$lon};
			}
		}
	}
	return $postcodelookup{$postcode};
}

sub addLatLonFromPostcodes {
	my @places = @_;
	my (@features,$i,$n,$postcode,$pc);
	$n = @places;
	
	for($i = 0; $i < $n; $i++){
		if(!$places[$i]{'lat'} && $places[$i]{'address'}){
			# Match to a UK postcode
			# https://stackoverflow.com/questions/164979/regex-for-matching-uk-postcodes
			if($places[$i]{'address'} =~ /([Gg][Ii][Rr] 0[Aa]{2})|((([A-Za-z][0-9]{1,2})|(([A-Za-z][A-Ha-hJ-Yj-y][0-9]{1,2})|(([A-Za-z][0-9][A-Za-z])|([A-Za-z][A-Ha-hJ-Yj-y][0-9][A-Za-z]?))))\s?[0-9][A-Za-z]{2})/){
				$postcode = $2;
				warning("\tFinding coordinates for $postcode\n");
				# Now we need to find the postcode areas e.g. LS, BD, M etc and load those files if we haven't
				$pc = getPostcode($postcode);
				if($pc->{'lat'}){
					$places[$i]->{'lat'} = $pc->{'lat'};
					$places[$i]->{'loc_pcd'} = JSON::XS::true;
				}
				if($pc->{'lon'}){
					$places[$i]->{'lon'} = $pc->{'lon'};
					$places[$i]->{'loc_pcd'} = JSON::XS::true;
				}
			}
			
		}
	}

	@features = @places;
	return @features;
}

sub getCentre {
	my $c = shift;
	if($c->{'type'} eq "Point"){
		return $c->{'coordinates'};
	}elsif($c->{'type'} eq "Polygon"){
		# Calculate the centre of a polygon https://en.wikipedia.org/wiki/Centroid#Of_a_polygon
		my $a = 0;
		my $b = 0;
		my $cx = 0;
		my $cy = 0;
		my $n = @{$c->{'coordinates'}}-1;	# Last coordinate should be a duplicate of the first
		for($i = 0; $i < $n-1; $i++){
			$b = (($c->{'coordinates'}[$i][0] * $c->{'coordinates'}[$i+1][1]) - ($c->{'coordinates'}[$i+1][0] * $c->{'coordinates'}[$i][1]));
			$a += $b;
			$cx += ($c->{'coordinates'}[$i][0] + $c->{'coordinates'}[$i+1][0])*$b;
			$cy += ($c->{'coordinates'}[$i][1] + $c->{'coordinates'}[$i+1][1])*$b;
		}

		if($a == 0){
			# The area is zero which may indicate this polygon intersects with itself so just return the first coordinates
			$cx = $c->{'coordinates'}[0][0];
			$cy = $c->{'coordinates'}[0][1];
		}else{
			$a *= 0.5;
			$cx *= 1/(6*$a);
			$cy *= 1/(6*$a);
		}

		# Check if coordinates look more like OS National Grid References
		if($cx > 180 && $cy > 90){
			($cx,$cy) = grid_to_ll($cx,$cy);
		}

		return ($cx,$cy);
	}
	return ();
}

sub getProperty {
	my $p = shift;
	my $d = shift;
	my @bits = split(/\-\>/,$p);
	my $n = @bits;
	my $out;
	if($n > 1){
		$key = shift(@bits);
		return getProperty(join("->",@bits),$d->{$key});
	}else{
		return $d->{$p};
	}
}

# https://code.activestate.com/recipes/577450-perl-url-encode-and-decode/
sub urldecode {
    my $s = shift;
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    $s =~ s/\+/ /g;
    return $s;
}

1;