package HTML5::DOM::Tree;
use strict;
use warnings;

use overload
	'""'		=> sub { shift->document->html }, 
	'@{}'		=> sub { [shift->document] }, 
	'bool'		=> sub { 1 }, 
	fallback	=> 1;

sub text { shift->document->text(@_) }
sub html { shift->document->html(@_) }

1;
__END__
