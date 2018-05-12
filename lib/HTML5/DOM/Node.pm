package HTML5::DOM::Node;
use strict;
use warnings;

use overload
	'""'		=> sub { shift->html }, 
	'@{}'		=> sub { shift->childrenNode->array }, 
	'%{}'		=> \&__attrHashAccess, 
	'bool'		=> sub { 1 }, 
	fallback	=> 1;

sub __attrHashAccess {
	my $self = shift;
	my %h;
	tie %h, 'HTML5::DOM::Node::_AttrHashAccess', $self;
	return \%h;
}

1;

package HTML5::DOM::Node::_AttrHashAccess;
use strict;
use warnings;

sub TIEHASH {
	my $p = shift;
	bless \shift, $p
}

sub FETCH {
	${shift()}->attr(shift);
}

sub STORE {
	${shift()}->attr(shift, shift);
}

1;
__END__
