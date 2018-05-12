package HTML5::DOM;
use strict;
use warnings;

# Node types
use HTML5::DOM::Node;
use HTML5::DOM::Element;
use HTML5::DOM::Comment;
use HTML5::DOM::DocType;
use HTML5::DOM::Text;

use HTML5::DOM::Tree;
use HTML5::DOM::Collection;
use HTML5::DOM::CSS;

our $VERSION = '0.01';
require XSLoader;

XSLoader::load('HTML5::DOM', $VERSION);

1;
__END__
