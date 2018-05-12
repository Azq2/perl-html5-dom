package HTML5::DOM::Tree;
use strict;
use warnings;

use overload
	'""'		=> sub { shift->html }, 
	'@{}'		=> sub { [shift->document] }, 
	'bool'		=> sub { 1 }, 
	fallback	=> 1;

1;
__END__
