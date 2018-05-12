#!/user/bin/perl
use warnings;
use strict;

use File::Slurp qw|read_file write_file|;
use File::Basename qw|dirname|;

my $files = [
	{
		file	=> dirname(__FILE__).'/../third_party/modest/source/modest/myosi.h', 
		prefix	=> 'MODEST_STATUS_'
	}, 
	{
		file	=> dirname(__FILE__).'/../third_party/modest/source/mycss/api.h', 
		prefix	=> 'MyCSS_STATUS_'
	}, 
	{
		file	=> dirname(__FILE__).'/../third_party/modest/source/myhtml/myosi.h', 
		prefix	=> 'MyHTML_STATUS_'
	}
];

my $tmp = "";
for my $cfg (@$files) {
	my $source = read_file($cfg->{file});
	my $prefix = $cfg->{prefix};
	while ($source =~ /($prefix[\w\d_-]+)\s*=\s*([x\d]+)/gim) {
		my ($key, $value) = ($1, eval $2);
		next if ($key eq $prefix."OK");
		$tmp .= "case $key:\n\treturn \"$key\";\n";
	}
}

write_file(dirname(__FILE__)."/../modest_errors.c", $tmp);
