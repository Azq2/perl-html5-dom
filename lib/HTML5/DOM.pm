package HTML5::DOM;
use strict;
use warnings;

use HTML5::DOM::Node;
use HTML5::DOM::Collection;

our $VERSION = '0.01';
require XSLoader;

XSLoader::load('HTML5::DOM', $VERSION);

1;
__END__
