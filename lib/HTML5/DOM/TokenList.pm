package HTML5::DOM::Text;
use strict;
use warnings;

use HTML5::DOM::Node;

sub new {
	my ($class, $node, $attr) = @_;
	my $self = {
		node	=> $node, 
		attr	=> $attr
	};
	bless $self, $class;
	return $self;
}

sub item {
	my ($self, $index) = shift;
	my $attr = $self->{node}->attr($self->{attr});
	my @items = split(/\s+/, $attr);
	return $items[$index];
}

sub has {
	my ($self, $token) = @_;
	my $attr = $self->{node}->attr($self->{attr});
	if (defined $attr) {
		return $attr =~ /(\s|^)\Q$attr\E(\s|$)/;
	}
	return 0;
}

sub contains { shift->has(@_) }

sub add {
	my ($self) = shift;
	my $attr = $self->{node}->attr($self->{attr});
	my @tokens = defined $attr ? split(/\s+/, $attr) : ();
	for my $token (@_) {
		return if ($self->has($token));
		push @tokens, $token;
	}
	$self->{node}->attr($self->{attr}, join(" ", @tokens));
	return $self;
}

sub remove {
	my ($self) = shift;
	my $attr = $self->{node}->attr($self->{attr});
	if (defined $attr) {
		for my $token (@_) {
			$attr =~ s/(\s|^)\Q$attr\E(\s|$)/ /;
			$attr =~ s/^\s+|\s+$//;
		}
		$self->{node}->attr($self->{attr}, $attr);
	}
	
	return $self;
}

sub replace {
	my ($self, $key, $value) = shift;
	my $attr = $self->{node}->attr($self->{attr});
	if (defined $attr) {
		$attr =~ s/(\s|^)\Q$key\E(\s|$)/$1$value$2/g;
	}
	return $self;
}

sub replace {
	
}

sub supports {
	
}

sub toggle {
	
}

sub entries {
	
}

sub forEach {
	
}

sub keys {
	
}

sub values {
	
}

1;
