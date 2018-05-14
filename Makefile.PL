use strict;
use utf8;
use Config;

use FindBin;
use ExtUtils::MakeMaker;

my $source_dir = $FindBin::Bin ."/third_party/modest/include";
my $port = "posix";
my $modest_source = "third_party/modest/source";

$port = 'windows_nt' if ($^O =~ /MSWin/i);

my $sources = [
	"modest.o", 
	"DOM.o"
];

WriteMakefile(
    AUTHOR			=> 'Kirill Zhumarin <kirill.zhumarin@gmail.com>',
    ABSTRACT		=> 'Super fast html5 DOM library with css selectors (based on Modest/MyHTML)',
    VERSION_FROM	=> 'lib/HTML5/DOM.pm',
    NAME			=> 'HTML5::DOM',
    LICENSE			=> 'WTFPL',
    LINKTYPE		=> 'dynamic',
    LIBS			=> ["-lpthread", "-lm"],
	INC				=> "-I$source_dir",
	OBJECT			=> join(" ", @$sources), 
	test			=> {TESTS => 't/*.t t/*/*.t'}
);
