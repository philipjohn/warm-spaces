#!/usr/bin/perl

use lib "./";
use utf8;
use JSON::XS;
use YAML::XS 'LoadFile';
use Data::Dumper;
use POSIX qw(strftime);
use Encode;
require "lib.pl";
binmode STDOUT, 'utf8';

$dir = "../docs/data/";
$rawdir = "raw/";
#makeDir($dir);
makeDir($rawdir);



@warmplaces;
$sources;

# Load the main config file
my $data = LoadFile('data.yml');

# How many directories do we have
my $n = @{$data->{'directories'}};

my $total = 0;
my $totalgeo = 0;
my $table = "";
my $key = $ARGV[0];

my ($i,$d,@features,$file,$json,$f,$rtnjson,$scraper,$json,$feat);

# Loop over the directories
for($i = 0, $j = 1; $i < $n; $i++, $j++){

	# Get the data for this one
	$d = $data->{'directories'}[$i];

	# Add an ID if we haven't provided one
	if(!$d->{'id'}){ $d->{'id'} = getID($d->{'title'}); }

	# Print the title of this one
	msg("$j: <cyan>$d->{'title'}<none> ($d->{'id'})\n");

	@features = ();

	# If there is data
	if($d->{'data'} && (!$key || ($key && $d->{'id'} eq $key))){

		# If the data type is GeoJSON
		if($d->{'data'}{'type'} eq "arcgis"){

			@features = getArcGIS($d);
			
		}elsif($d->{'data'}{'type'} eq "geojson"){

			@features = getGeoJSON($d);

		}elsif($d->{'data'}{'type'} eq "xls"){

			@features = getXLSX($d);

		}elsif($d->{'data'}{'type'} eq "storepoint"){

			# Get the data (if we don't have a cached version)
			$file = getDataFromURL($d);

			msg("\tProcessing Storepoint data\n");
			$json = getJSON($file);

			$d->{'count'} = @{$json->{'results'}{'locations'}};
			if($d->{'count'} == 0){
				warning("\tNo features for $d->{'title'}\n");
			}else{

				# For each feature 
				for($f = 0; $f < $d->{'count'}; $f++){
					$rtnjson = parseStorepointFeature($json->{'results'}{'locations'}[$f],$d->{'data'}{'keys'});
					$rtnjson->{'_source'} = $d->{'id'};
					push(@features,$rtnjson);
				}

				@features = addLatLonFromPostcodes(@features);
			}

		}elsif($d->{'data'}{'type'} eq "googlemap"){
			
			@features = getGoogleMap($d);
			
		}elsif($d->{'data'}{'type'} eq "csv"){
			
			@features = getCSV($d);
			
		}elsif($d->{'data'}{'type'} eq "html"){

			# Find the scraping file
			$scraper = "scrapers/$d->{'id'}.pl";

			if(-e $scraper){

				# Get the data (if we don't have a cached version)
				$file = getDataFromURL($d);

				msg("\tParsing web page\n");

				$str = `perl $scraper $file`;

				if(-e $str){
					open(FILE,"<:utf8",$str);
					@lines = <FILE>;
					close(FILE);
					$str = join("",@lines);

					eval {
						$json = JSON::XS->new->decode($str);
					};
					if($@){ warning("\tInvalid output from scraper.\n".$str); }

					for($f = 0; $f < @{$json}; $f++){
						$json->[$f]{'_source'} = $d->{'id'};
						push(@features,$json->[$f]);
					}

					@features = addLatLonFromPostcodes(@features);

				}else{
					warning("\tNo JSON returned from scraper\n");
				}
			}else{
				warning("\tNo scaper at scrapers/$d->{'id'}.pl\n");
			}

		}elsif($d->{'data'}{'type'} eq "squarespace"){

			@features = getSquareSpace($d);
			@features = addLatLonFromPostcodes(@features);

		}
		
		$d->{'count'} = @features;
		$d->{'geocount'} = 0;
		for($f = 0; $f < @features; $f++){
			if($features[$f]{'lat'} && $features[$f]{'lon'}){
				# Truncate coordinates to remove unnecessary precision (no need for better than 1m)
				$features[$f]{'lat'} = sprintf("%0.5f",$features[$f]{'lat'})+0;
				$features[$f]{'lon'} = sprintf("%0.5f",$features[$f]{'lon'})+0;
				$d->{'geocount'}++;
			}

			# Fix issue with tabs inside properties
			foreach $feat (sort(keys(%{$features[$f]}))){
				if($features[$f]{$feat} =~ /[\t]/){
					$features[$f]{$feat} =~ s/[\t]$//g;
					$features[$f]{$feat} =~ s/[\t]/ /g;
				}
				$features[$f]{$feat} =~ s/[\s\t]{2,}/ /g;
				$features[$f]{$feat} =~ s/(^\s|\s$)//g;
				if(!$features[$f]{$feat}){ delete $features[$f]{$feat}; }
			}
			push(@warmplaces,$features[$f]);
		}

		msg("\tAdded $d->{'count'} features ($d->{'geocount'} geocoded).\n");
		$total += $d->{'count'};
		$totalgeo += $d->{'geocount'};
			

	}
	$table .= "<tr>";
	$table .= "<td><a href=\"$d->{'url'}\">$d->{'title'}</a></td>";
	$table .= "<td>".($d->{'count'} ? $d->{'count'} : "?")."</td>";
	$table .= "<td".($d->{'geocount'} ? " class=\"c13-bg\"":"").">".($d->{'geocount'} ? $d->{'geocount'} : "")."</td>";
	$table .= "<td>".($d->{'map'} && $d->{'map'}{'url'} ? "<a href=\"$d->{'map'}{'url'}\">Map</a>":"")."</td>";
	$table .= "<td>".($d->{'register'} && $d->{'register'}{'url'} ? "<a href=\"$d->{'register'}{'url'}\">Add a warm place</a>":"")."</td>";
	$table .= "<td>".($d->{'notes'} ? $d->{'notes'}:"")."</td>";
	$table .= "</tr>\n";

	$sources->{$d->{'id'}} = $d;
	if($sources->{$d->{'id'}}{'count'}){
		$sources->{$d->{'id'}}{'count'} += 0;
	}
	if($sources->{$d->{'id'}}{'geocount'}){
		$sources->{$d->{'id'}}{'geocount'} += 0;
	}
}
open($fh,">:utf8",$dir."places.json");
print $fh tidyJSON(\@warmplaces,1);
close($fh);

open($fh,">:utf8",$dir."sources.json");
print $fh tidyJSON($sources,2);
close($fh);

open($fh,">:utf8",$dir."summary.html");
print $fh "<p>As of <time datetime=\"".strftime("%FT%X%z", localtime)."\">".strftime("%e %B %Y (%R)", localtime)."</time>.</p>\n";
print $fh "<table>\n";
print $fh "<thead><tr><th>Directory</th><th>Entries</th><th>Geocoded</th><th>Map</th><th>Register</th><th>Notes</th></thead></tr>\n";
print $fh "<tbody>\n";
print $fh $table;
print $fh "</tbody>\n";
print $fh "</table>\n";
close($fh);




msg("Added $total features in total ($totalgeo geocoded).\n");

################
# SUBROUTINES
sub getID {
	my $str = $_[0];
	$str = lc($str);
	$str =~ s/[^a-z0-9\-\_]/\_/g;
	return $str;
}

sub parseStorepointFeature {
	my $f = shift;
	my $keys = shift;
	my $json = {'hours'=>{}};
	my @fields = ("title","address","lat","lon","description","accessibility","type");
	my($i,@days);

	for($i = 0; $i < @fields; $i++){
		if($f->{$fields[$i]}){ $json->{$fields[$i]} = $f->{$fields[$i]}; }
		if($keys->{$fields[$i]} && $f->{$keys->{$fields[$i]}}){ $json->{$fields[$i]} = $f->{$keys->{$fields[$i]}}; }
	}

	# Explicit days
	@days = ("monday","tuesday","wednesday","thursday","friday","saturday","sunday");
	$json->{'hours'}{'opening'} = "";
	for($i = 0; $i < @days; $i++){
		if($f->{$days[$i]}){ $json->{'hours'}{$days[$i]} = $f->{$days[$i]}; }
		if($keys->{$days[$i]} && $f->{$keys->{$days[$i]}}){ $json->{'hours'}{$days[$i]} = $f->{$keys->{$days[$i]}}; }
		$json->{'hours'}{$days[$i]} =~ s/(^[\s\t]|[\s\t]$)//g;
	}
	$json->{'hours'} = parseOpeningHours($json->{'hours'});
	if(!$json->{'hours'}{'_text'} && !$json->{'hours'}{'opening'}){
		delete $json->{'hours'};
	}

	return $json;
}

sub parseGeoJSONFeature {
	my $f = shift;
	my $keys = shift;
	my $json = {};
	my @fields = ("title","address","lat","lon","description","accessibility","type");
	my $props = "properties";
	if(!$f->{$props} && $f->{'attributes'}){
		$props = "attributes";
	}
	my ($i,@days,$key,$tempk,$v);
	for($i = 0; $i < @fields; $i++){
		if($f->{$props}{$fields[$i]}){ $json->{$fields[$i]} = $f->{$props}{$fields[$i]}; }
		if($keys->{$fields[$i]} && $f->{$props}{$keys->{$fields[$i]}}){ $json->{$fields[$i]} = $f->{$props}{$keys->{$fields[$i]}}; }
	}

	# Explicit days
	@days = ("monday","tuesday","wednesday","thursday","friday","saturday","sunday");
	for($i = 0; $i < @days; $i++){
		if($f->{$props}{$days[$i]}){ $json->{'hours'}{$days[$i]} = $f->{$props}{$days[$i]}; }
		if($keys->{$days[$i]} && $f->{$props}{$keys->{$days[$i]}}){ $json->{'hours'}{$days[$i]} = $f->{$props}{$keys->{$days[$i]}}; }
	}

	# Replacement values
	foreach $key (keys(%{$keys})){
		# Do we have the lookup key
		if($f->{$props}{$keys->{$key}}){
			# Save to the replacement key
			$v = $f->{$props}{$keys->{$key}};
			$v =~ s/(^\s|\s$)//;
			if($v){
				$json->{$key} = $v;
			}
		}
	}
	foreach $key (keys(%{$keys})){
		if($keys->{$key} =~ /\{\{ ?(.*?) ?\}\}/){
			$tempk = $keys->{$key};
			while($tempk =~ /\{\{ ?(.*?) ?\}\}/){
				$v = $f->{$props}{$1};
				$v =~ s/(^\s|\s$)//;
				$tempk =~ s/\{\{ ?(.*?) ?\}\}/$v/sg;
				$tempk =~ s/[\n]/ /g;
			}
			$json->{$key} = $tempk;
		}
	}


	# Deal with hours
	if($f->{$props}{'hours'}){ $json->{'hours'} = {'_text'=>$f->{$props}{'hours'} }; }
	if($keys->{'hours'} && $f->{$props}{$keys->{'hours'}}){ $json->{'hours'} = {'_text'=> $f->{$props}{$keys->{'hours'}} }; }

	if($json->{'hours'}){
		if(ref $json->{'hours'} eq ref ""){ $json->{'hours'} = {'_text'=>$json->{'hours'} }; }
		$json->{'hours'} = parseOpeningHours($json->{'hours'});
		if(!$json->{'hours'}{'opening'}){ delete $json->{'hours'}{'opening'}; } 
	}

	# If we haven't explicitly been sent lat/lon in the properties we get it from the coordinates
	if(!$json->{'lat'}){ $json->{'lat'} = ($f->{'geometry'}{'y'}||$f->{'geometry'}{'coordinates'}[1]); }
	if(!$json->{'lon'}){ $json->{'lon'} = ($f->{'geometry'}{'x'}||$f->{'geometry'}{'coordinates'}[0]); }
	return $json;
}

sub getXLSX {

	my $d = shift;

	my ($file,$str,$t,@strings,$sheet,$props,$row,$col,$attr,$cols,@rows,$rowdata,@geo,@features,$c,$r,$n,$datum);

	# Get the data (if we don't have a cached version)
	$file = getDataFromURL($d);
	
	msg("\tUnzipping xlsx to extract data from $d->{'data'}{'sheet'}\n");

	# First we need to get the sharedStrings.xml
	$str = decode_utf8(join("",`unzip -p $file xl/sharedStrings.xml`));
	while($str =~ s/<si>(.*?)<\/si>//){
		$t = $1;
		$t =~ s/<[^\>]+>//g;
		push(@strings,$t);
	}	

	$str = decode_utf8(join("",`unzip -p $file xl/worksheets/$d->{'data'}{'sheet'}.xml`));

	if($str =~ /<sheetData>(.*?)<\/sheetData>/){
		$sheet = $1;
		while($sheet =~ s/<row([^\>]*?)>(.*?)<\/row>//){
			$props = $1;
			$row = $2;
			$attr = {};
			while($props =~ s/([^\s]+)="([^\"]+)"//){ $attr->{$1} = $2; }
			$rowdata = {'content'=>$row,'attr'=>$attr,'cols'=>()};
			while($row =~ s/<c([^\>]*?)>(.*?)<\/c>//){
				$props = $1;
				$col = $2;
				$col =~ s/<[^\>]+>//g;
				$attr = {};
				while($props =~ s/([^\s]+)="([^\"]+)"//){ $attr->{$1} = $2; }
				if($attr->{'r'} =~ /^([A-Z]+)([0-9]+)/){
					$c = $1;
					$n = $2;
#					if(!$cols->{$c}){ $cols->{$c} = (); }
#					$cols->{$c}[$n-1] = $strings[$col];
					$rowdata->{'cols'}{$c} = $strings[$col];
				}
			}
			push(@rows,$rowdata);
		}
	}

	for($r = 0; $r < @rows; $r++){
		if($rows[$r]->{'attr'}{'r'} >= $d->{'data'}{'startrow'}){
			$datum = {};
			foreach $key (keys(%{$d->{'data'}{'keys'}})){
				if($rows[$r]->{'cols'}{$d->{'data'}{'keys'}{$key}}){
					$datum->{$key} = $rows[$r]->{'cols'}{$d->{'data'}{'keys'}{$key}};
				}
				
			}
			push(@features,$datum);
		}
	}

	# Add lat,lon from postcodes
	return addLatLonFromPostcodes(@features);
}

sub getGeoJSON {

	my $d = shift;

	my ($file,$geojson,$f,$json,@features);

	# Get the data (if we don't have a cached version)
	$file = getDataFromURL($d);

	msg("\tProcessing GeoJSON\n");
	$geojson = getJSON($file);

	# How many features in the GeoJSON
	$d->{'count'} = @{$geojson->{'features'}};
	if($d->{'count'} == 0){
		warning("\tNo features for $d->{'title'}\n");
	}else{

		# For each feature 
		$d->{'geocount'} = $d->{'count'};
		for($f = 0; $f < $d->{'count'}; $f++){
			$json = parseGeoJSONFeature($geojson->{'features'}[$f],$d->{'data'}{'keys'});
			$json->{'_source'} = $d->{'id'};
			push(@features,$json);
		}
		
		@features = addLatLonFromPostcodes(@features);
	}
	return @features;
}

sub getArcGIS {
	my $d = shift;

	my ($file,$geojson,$f,@features,$json);

	# Make sure we have the correct output spatial reference
	$d->{'data'}{'url'} =~ s/outSR=27700/outSR=4326/g;
	$d->{'data'}{'url'} =~ s/f=pbf/f=geojson/g;

	# Get the data (if we don't have a cached version)
	$file = getDataFromURL($d);

	msg("\tProcessing GeoJSON\n");
	$geojson = getJSON($file);

	# How many features in the GeoJSON
	$d->{'count'} = @{$geojson->{'features'}};
	if($d->{'count'} == 0){
		warning("\tNo features for $d->{'title'}\n");
	}else{

		# For each feature 
		$d->{'geocount'} = $d->{'count'};
		for($f = 0; $f < $d->{'count'}; $f++){
			$json = parseGeoJSONFeature($geojson->{'features'}[$f],$d->{'data'}{'keys'});
			$json->{'_source'} = $d->{'id'};
			push(@features,$json);
		}
		#@features = addLatLonFromPostcodes(@features);
	}
	return @features;
}

sub cleanCDATA {
	my $str = $_[0];
	$str =~ s/(^<!-?\[CDATA\[|\]\]>$)//g;
	return $str;
}

sub getGoogleMap {
	
	my $d = shift;
	my $keys = shift;

	my ($dir,$str,$file,$kmzfile,$kmzurl,$placemarks,$lon,$lat,$alt,$c,$url,$entry,$props,$remove,$k,@entries,$hrs,$parse,$re,$p2,@matches,$txt,$key,$v,$tempv);

	$url = $d->{'data'}{'url'};
	$file = $rawdir.$d->{'id'}.".html";
	$kmzfile = $rawdir.$d->{'id'}.".kmz";

	msg("\tGetting Google Maps pageData\n");
	getURLToFile($url,$file);
	$str = join("",getFileContents($file));
	if($str =~ /\"(https:\/\/www.google.com\/maps\/d\/kml\?mid[^\"]+)\\"/){
		$kmzurl = $1;
		$kmzurl =~ s/\\\\u003d/=/g;
		$kmzurl =~ s/\\\\u0026/\&/g;
	}
	msg("\tGetting Google Maps kmz from $kmzurl\n");
	getURLToFile($kmzurl,$kmzfile);
	msg("\tUnzipping kmz\n");
	$str = decode_utf8(join("",`unzip -p $kmzfile doc.kml`));

	while($str =~ s/<Placemark>(.*?)<\/Placemark>//s){
		$placemark = $1;
		$entry = {};
		$props = {};
		if($placemark =~ /<name>(.*?)<\/name>/s){ $entry->{'name'} = cleanCDATA($1); }
		if($placemark =~ /<coordinates>(.*?)<\/coordinates>/s){
			$c = cleanCDATA($1);
			$c =~ s/(^ *| *$)//g;
			$c =~ s/[\n\r\t\s]+//g;
			($lon,$lat,$alt) = split(/,/,$c);
			$entry->{'lat'} = $lat+0;
			$entry->{'lon'} = $lon+0;
		}
		if($placemark =~ /<ExtendedData>(.*?)<\/ExtendedData>/s){
			$parse = $1;
			while($parse =~ s/<Data name="([^\"]+)">(.*?)<\/Data>//s){
				$k = $1;
				$v = $2;
				if($v =~ s/^.*<value>(.*?)<\/value>.*$/$1/gs){
					$props->{$k} = $v;
				}
			}
		}else{
			if($placemark =~ /<description>(.*?)<\/description>/s){
				$entry->{'description'} = cleanCDATA($1);
				$remove = {};
				if($d->{'data'}{'parse'}){
					$parse = $d->{'data'}{'parse'}."";
					@reps = ();
					while($parse =~ s/\{\{ ?([^\}]+) ?\}\}/\(.*?\)/){
						push(@reps,$1);
					}
					$re = qr/^$parse$/is;
					@matches = $entry->{'description'} =~ $re;
					if(@matches > 0){
						for($p2 = 0; $p2 < @reps; $p2++){
							$reps[$p2] =~ s/(^[\s]+|[\s]+$)//g;
							$txt = parseText($matches[$p2]);
							if($txt){ $props->{$reps[$p2]} = $txt; }
						}
					}
					$remove{'description'} = 1;
				}
			}
		}

		if($d->{'data'}{'keys'}){

			# Replace any replacements in the $props structure and add them to the $entry structure
			foreach $key (keys(%{$d->{'data'}{'keys'}})){
				$v = $d->{'data'}{'keys'}{$key};
				if($props->{$v} && !$entry->{$key}){
					$entry->{$key} = $props->{$v};
				}elsif($v =~ /\{\{ ?(.*?) ?\}\}/){
					$v =~ s/\{\{ ?(.*?) ?\}\}/$props->{$1}/sg;
					$v =~ s/[\n]//g;
					$entry->{$key} = $v;
				}
			}

			# Build replacements
			foreach $k (keys(%{$d->{'data'}{'keys'}})){
				if($entry->{$d->{'data'}{'keys'}{$k}}){
					$entry->{$k} = "".$entry->{$d->{'data'}{'keys'}{$k}};
					$remove->{$d->{'data'}{'keys'}{$k}} = 1;
				}
			}
			if(!$entry->{'hours'} && $entry->{$d->{'data'}{'keys'}{'hours'}}){
				$entry->{'hours'} = $entry->{$d->{'data'}{'keys'}{'hours'}};
				$entry->{'hours'} =~ s/<br>/ /;
				$entry->{'hours'} =~ s/[\s]/ /;
				$entry->{'hours'} =~ s/[^0-9A-Za-z\-\,\.\:\;\s\[\]]/ /;
				if($d->{'data'}{'keys'}{'hours'} eq "description"){ $remove{'description'} = 1; }
			}
			$entry->{'description'} = parseText($entry->{'description'});
			if(!$entry->{'description'}){ $remove{'description'}; }
			if($d->{'data'}{'keys'}{'description'}){
				delete $remove->{'description'};
			}
		}
		foreach $k (keys(%{$remove})){
			delete $entry->{$k};
		}
		if($entry->{'hours'}){
			$entry->{'hours'} = parseOpeningHours({'_text'=>$entry->{'hours'}});
			if(!$entry->{'hours'}{'opening'}){ delete $entry->{'hours'}{'opening'}; }
		}
		$entry->{'_source'} = $d->{'id'};
		push(@entries,$entry);
	}
	
	@entries = addLatLonFromPostcodes(@entries);

	return @entries;
}

sub getSquareSpace {
	my $d = shift;
	my $keys = shift;
	my ($url,$page,$p,@items,$purl,$i,$n,$json,$f,$cache,$attempts);
	my @fields = ("title","address","lat","lon","description","accessibility","type");

	#e.g. https://warmspaces.org/locations?format=json&cache=2022-11-24T00-2
	# Use cache parameter to make sure the pages don't change as we step through them
	$cache = strftime("%FT%H-%M",gmtime);
	$url = $d->{'data'}{'url'}."?format=json&cache=$cache";

	$p = 1;
	$page = $rawdir.$d->{'id'}."-$p.json";
	getURLToFile($url,$page);
	$json = getJSON($page);
	$attempts = 1;
	
	@items = @{$json->{'items'}};
	
	while($json->{'pagination'}{'nextPage'}){
		$purl = $url."&offset=$json->{'pagination'}{'nextPageOffset'}";
		$p++;
		$page = $rawdir.$d->{'id'}."-$p.json";
		# Get the file but pass in any delay value we already have
		$attempts = getURLToFile($purl,$page,$attempts);
		$json = getJSON($page);
		@items = (@items,@{$json->{'items'}});
		$n = @items;
	}
	
	@features;

	for($i = 0; $i < @items; $i++){
			
		$json = {};
		for($f = 0; $f < @fields; $f++){
			if($items[$i]{$fields[$f]}){ $json->{$fields[$f]} = $items[$i]{$fields[$f]}; }
			if($keys->{$fields[$f]} && $items[$i]{$keys->{$fields[$f]}}){ $json->{$fields[$f]} = $items[$i]{$keys->{$fields[$f]}}; }
		}
		$json->{'lat'} = $items[$i]{'location'}{'mapLat'}+0;
		$json->{'lon'} = $items[$i]{'location'}{'mapLng'}+0;
		$json->{'address'} = $items[$i]{'location'}{'addressLine1'}.", ".$items[$i]{'location'}{'addressLine2'};
		if($items[$i]{'excerpt'} =~ /<a href="([^\"]+)">Find out more<\/a>/){ $json->{'url'} = $1; }
		if($items[$i]{'excerpt'} =~ /<strong>(<br>)?Opening Hours: *<\/strong> ?(.*?)</){ $json->{'hours'} = {'_text'=>$2}; }
		$json->{'hours'} = parseOpeningHours($json->{'hours'});

		$json->{'_source'} = $d->{'id'};
		
		push(@features,$json);
	}
	return @features;
}

sub getCSV {
	my $d = shift;

	my ($file,@lines,$str,@rows,@cols,@header,$r,$c,@features,$data,$key,$k,$f);
	my @fields = ("title","address","lat","lon","description","accessibility","type","hours");

	# Get the data (if we don't have a cached version)
	$file = getDataFromURL($d);


	msg("\tProcessing CSV\n");
	open(FILE,"<:utf8",$file);
	@lines = <FILE>;
	close(FILE);
	$str = join("",@lines);
	@rows = split(/\r\n/,$str);
	for($r = 0; $r < @rows; $r++){
		@cols = split(/,(?=(?:[^\"]*\"[^\"]*\")*(?![^\"]*\"))/,$rows[$r]);
		if($r < $d->{'data'}{'startrow'}-1){
			# Header
			if(!@header){
				@header = @cols;
			}else{
				for($c = 0; $c < @cols; $c++){
					$header[$c] .= "\n".$cols[$c];
				}
			}
		}else{
			if($r == $d->{'data'}{'startrow'}-1){
				# Process header line - rename columns based on the defined keys
				for($c = 0; $c < @cols; $c++){
					$key = $header[$c];
					foreach $k (keys(%{$d->{'data'}{'keys'}})){
						if($d->{'data'}{'keys'}{$k} eq $key){
							$header[$c] = $k;
							last;
						}
					}
				}
			}
			$data = {'_source'=>$d->{'id'}};
			for($c = 0; $c < @cols; $c++){
				$cols[$c] =~ s/(^\"|\"$)//g;
				$needed = 0;
				for($f = 0; $f < @fields; $f++){
					if($header[$c] eq $fields[$f]){ $needed = 1; }
				}
				if($needed){ $data->{$header[$c]} = $cols[$c]; }
				if($header[$c] eq "hours"){ $data->{'hours'} = parseOpeningHours({'_text'=>$cols[$c]}); }
			}
			push(@features,$data);
		}
	}


	# Add lat,lon from postcodes if we don't have them
	return addLatLonFromPostcodes(@features);
}
