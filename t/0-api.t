use Test::More;
use warnings;
use strict;

require_ok('HTML5::DOM');

# test static API
can_ok('HTML5::DOM', qw(new));
can_ok('HTML5::DOM::Collection', qw(new));
can_ok('HTML5::DOM::Encoding', qw(
	id2name name2id detectAuto detect detectRussian detectUnicode
	detectByPrescanStream detectByCharset detectBomAndCut
));
can_ok('HTML5::DOM::CSS', qw(new));
can_ok('HTML5::DOM::CSS::Selector', qw(new));

#####################################
# HTML5::DOM
#####################################

# new without options
my $parser = HTML5::DOM->new;
isa_ok($parser, 'HTML5::DOM', 'create parser without options');

# new with options
$parser = HTML5::DOM->new({
	threads	=> 2
});
isa_ok($parser, 'HTML5::DOM', 'create parser with options');

# test api
can_ok($parser, qw(parse parseChunkStart parseChunk parseChunkEnd));

# test html parsing with threads
my $tree = $parser->parse('<div id="test">bla bla<!-- o_O --></div>');
isa_ok($tree, 'HTML5::DOM::Tree', 'parse with threads');

# test html parsing without threads
$tree = $parser->parse('<div id="test">bla bla<!-- o_O --></div>', {threads => 0});
isa_ok($tree, 'HTML5::DOM::Tree', 'parse without threads');

# test api
can_ok($tree, qw(
	createElement createComment createTextNode parseFragment document root head body
	at querySelector find querySelectorAll findId getElementById findTag getElementsByTagName
	findClass getElementsByClassName findAttr getElementByAttribute encoding encodingId
	tag2id id2tag namespace2id id2namespace wait parsed parser
));

# test chunks
isa_ok($parser->parseChunkStart(), 'HTML5::DOM');
isa_ok($parser->parseChunk('<div'), 'HTML5::DOM');
isa_ok($parser->parseChunk('>ololo'), 'HTML5::DOM');
isa_ok($parser->parseChunk('</div>'), 'HTML5::DOM');
isa_ok($parser->parseChunk('ololo'), 'HTML5::DOM');
isa_ok($parser->parseChunkEnd, 'HTML5::DOM::Tree');

#####################################
# HTML5::DOM::Tree
#####################################

# wait
isa_ok($tree->wait, "HTML5::DOM::Tree");
ok($tree->parsed == 1, "parsed");

# basic tree api
isa_ok($tree->root, 'HTML5::DOM::Element');
ok($tree->root->tag eq 'html', 'root tag name');
ok($tree->root->tagId == HTML5::DOM->TAG_HTML, 'root tag id');

isa_ok($tree->head, 'HTML5::DOM::Element');
ok($tree->head->tag eq 'head', 'head tag name');
ok($tree->head->tagId == HTML5::DOM->TAG_HEAD, 'head tag id');

isa_ok($tree->body, 'HTML5::DOM::Element');
ok($tree->body->tag eq 'body', 'body tag name');
ok($tree->body->tagId == HTML5::DOM->TAG_BODY, 'body tag id');

isa_ok($tree->document, 'HTML5::DOM::Document');
ok($tree->document->tag eq '-undef', 'document tag name');
ok($tree->document->tagId == HTML5::DOM->TAG__UNDEF, 'document tag id');

# createElement with namespace
my $new_node = $tree->createElement("mycustom", "svg");
isa_ok($new_node, 'HTML5::DOM::Element');
ok($new_node->tag eq 'mycustom', 'mycustom tag name');
ok($new_node->namespace eq 'SVG', 'mycustom namespace name');
ok($new_node->namespaceId eq HTML5::DOM->NS_SVG, 'mycustom namespace id');
ok($new_node->tagId == $tree->tag2id('mycustom'), 'mycustom tag id');

# createElement with default namespace
$new_node = $tree->createElement("mycustom2");
isa_ok($new_node, 'HTML5::DOM::Element');
ok($new_node->namespace eq 'HTML', 'mycustom2 namespace name');
ok($new_node->namespaceId eq HTML5::DOM->NS_HTML, 'mycustom2 namespace id');

# createComment
$new_node = $tree->createComment(" my comment >_< ");
isa_ok($new_node, 'HTML5::DOM::Comment');
ok($new_node->text eq ' my comment >_< ', 'Comment serialization text');
ok($new_node->html eq '<!-- my comment >_< -->', 'Comment serialization html');

# createTextNode
$new_node = $tree->createTextNode(" my text >_< ");
isa_ok($new_node, 'HTML5::DOM::Text');
ok($new_node->text eq ' my text >_< ', 'Text serialization text');
ok($new_node->html eq ' my text &gt;_&lt; ', 'Text serialization html');

# parseFragment
$new_node = $tree->parseFragment(" <div>its <b>a</b><!-- ololo --> fragment</div> ");
isa_ok($new_node, 'HTML5::DOM::Fragment');
ok($new_node->text eq ' its a fragment ', 'Fragment serialization text');
ok($new_node->html eq ' <div>its <b>a</b><!-- ololo --> fragment</div> ', 'Fragment serialization html');

# encoding
ok($tree->encoding() eq "UTF-8", "encoding");
ok($tree->encodingId() == HTML5::DOM::Encoding->UTF_8, "encodingId");

# tag2id
ok($tree->tag2id("div") == HTML5::DOM->TAG_DIV, "tag2id");
ok($tree->tag2id("DiV") == HTML5::DOM->TAG_DIV, "tag2id");
ok($tree->tag2id("blablabla") == HTML5::DOM->TAG__UNDEF, "tag2id not exists");

# id2tag
ok($tree->id2tag(HTML5::DOM->TAG_DIV) eq "div", "id2tag");
ok(!defined $tree->id2tag(8274242), "id2tag not exists");

# namespace2id
ok($tree->namespace2id("SvG") == HTML5::DOM->NS_SVG, "namespace2id");
ok($tree->namespace2id("svg") == HTML5::DOM->NS_SVG, "namespace2id");
ok($tree->namespace2id("blablabla") == HTML5::DOM->NS_UNDEF, "namespace2id not exists");

# id2namespace
ok($tree->id2namespace(HTML5::DOM->NS_SVG) eq "SVG", "id2namespace");
ok(!defined $tree->id2namespace(8274242), "id2namespace not exists");

# parser
isa_ok($tree->parser, 'HTML5::DOM');
ok($tree->parser == $parser, 'parser');

# finders
$tree = $parser->parse('
	<!DOCTYPE html>
	<div id="test0" some-attr="ololo trololo" class="red blue">
		<div class="yellow" id="test1"></div>
	</div>
	<div id="test2" some-attr="ololo" class="blue">
		<div class="yellow" id="test3"></div>
	</div>
	
	<span test-attr-eq="test"></span>
	<span test-attr-eq="testt"></span>
	
	<span test-attr-space="wefwef   test   wefewfew"></span>
	<span test-attr-space="wefewwef testt wewe"></span>
	
	<span test-attr-dash="test-fwefwewfe"></span>
	<span test-attr-dash="testt-"></span>
	
	<span test-attr-substr="wefwefweftestfweewfwe"></span>
	
	<span test-attr-prefix="testewfwefewwf"></span>
	
	<span test-attr-suffix="ewfwefwefweftest"></span>
');

# querySelector + at
for my $method (qw|at querySelector|) {
	isa_ok($tree->$method('div'), 'HTML5::DOM::Element');
	ok($tree->$method('div')->attr("id") eq 'test0', "$method: find div");
	ok(!defined $tree->$method('xuj'), "$method: not found");
}

# findId + getElementById
for my $method (qw|findId getElementById|) {
	isa_ok($tree->$method('test2'), 'HTML5::DOM::Element');
	ok($tree->$method('test2')->attr("id") eq 'test2', "$method: find #test2");
	ok(!defined $tree->$method('xuj'), "$method: not found");
}

# find + querySelectorAll
for my $method (qw|find querySelectorAll|) {
	isa_ok($tree->$method('.blue'), 'HTML5::DOM::Collection');
	isa_ok($tree->$method('.ewfwefwefwefwef'), 'HTML5::DOM::Collection');
	ok($tree->$method('.blue')->length == 2, "$method: find .blue");
	ok($tree->$method('.bluE')->length == 0, "$method: find .bluE");
	ok($tree->$method('.ewfwefwefwefwef')->length == 0, "$method: not found");
	ok($tree->$method('.blue')->item(1)->attr("id") eq "test2", "$method: check result element");
}

# findTag + getElementsByTagName
for my $method (qw|findTag getElementsByTagName|) {
	isa_ok($tree->$method('div'), 'HTML5::DOM::Collection');
	isa_ok($tree->$method('ewfwefwefwefwef'), 'HTML5::DOM::Collection');
	ok($tree->$method('div')->length == 4, "$method: find div");
	ok($tree->$method('dIv')->length == 4, "$method: find dIv");
	ok($tree->$method('ewfwefwefwefwef')->length == 0, "$method: not found");
	ok($tree->$method('div')->item(0)->attr("id") eq "test0", "$method: check result element");
}

# findClass + getElementsByClassName
for my $method (qw|findClass getElementsByClassName|) {
	isa_ok($tree->$method('blue'), 'HTML5::DOM::Collection');
	isa_ok($tree->$method('ewfwefwefwefwef'), 'HTML5::DOM::Collection');
	ok($tree->$method('blue')->length == 2, "$method: find .blue");
	ok($tree->$method('red')->length == 1, "$method: find .red");
	ok($tree->$method('bluE')->length == 0, "$method: find .bluE");
	ok($tree->$method('ewfwefwefwefwef')->length == 0, "$method: not found");
	ok($tree->$method('yellow')->item(0)->attr("id") eq "test1", "$method: check result element");
}

# findAttr + getElementByAttribute
for my $method (qw|findAttr getElementByAttribute|) {
	for my $cmp (qw(= ~ | * ^ $)) {
		for my $i ((0, 1)) {
			my $attrs = {
				'='	=> 'test-attr-eq', 
				'~'	=> 'test-attr-space', 
				'|'	=> 'test-attr-dash', 
				'*'	=> 'test-attr-substr', 
				'^'	=> 'test-attr-prefix', 
				'$'	=> 'test-attr-suffix', 
			};
			
			my $values = [['test', 'tesT'], ['tEsT', 'test2']];
			
			# test found
			my $collection = $tree->$method($attrs->{$cmp}, $values->[$i]->[0], $i, $cmp);
			isa_ok($collection, 'HTML5::DOM::Collection');
			ok($collection->length == 1, "$method(".$attrs->{$cmp}.", $cmp, $i): found ".$collection->length);
			
			# test not found
			$collection = $tree->$method($attrs->{$cmp}, $values->[$i]->[1], $i, $cmp);
			isa_ok($collection, 'HTML5::DOM::Collection');
			ok($collection->length == 0, "$method(".$attrs->{$cmp}.", $cmp, $i): not found ".$collection->length);
		}
	}
}

# compatMode
ok($parser->parse('<div></div>')->compatMode eq 'BackCompat', 'compatMode: BackCompat');
ok($parser->parse('<!DOCTYPE html><div></div>')->compatMode eq 'CSS1Compat', 'compatMode: CSS1Compat');

#####################################
# HTML5::DOM::Node
#####################################

my @node_methods = qw(
	tag nodeName tagId namespace namespaceId tree nodeType next nextElementSibling
	prev previousElementSibling nextNode nextSibling prevNode previousSibling 
	first firstElementChild last lastElementChild firstNode firstChild 
	lastNode lastChild html innerHTML outerHTML text innerText outerText textContent
	nodeHtml nodeValue data isConnected parent parentElement document ownerDocument
	append appendChild prepend prependChild replace replaceChild before insertBefore
	after insertAfter remove removeChild clone cloneNode void selfClosed position
	isSameNode wait parsed
);
my @element_methods = qw(
	children childrenNode childNodes attr removeAttr getAttribute setAttribute
	removeAttribute at querySelector find querySelectorAll findId getElementById
	findTag getElementsByTagName findClass getElementsByClassName findAttr
	getElementByAttribute getDefaultBoxType
);

# check elements + nodeType
my $el_node = $tree->createElement("div");
can_ok($el_node, @node_methods);
can_ok($el_node, @element_methods);
ok(ref($el_node) eq 'HTML5::DOM::Element', 'check element ref');
ok($el_node->nodeType == $el_node->ELEMENT_NODE, 'nodeType == ELEMENT_NODE');

# check comments + nodeType
my $comment_node = $tree->createComment("comment...");
can_ok($comment_node, @node_methods);
ok(ref($comment_node) eq 'HTML5::DOM::Comment', 'check comment ref');
ok($comment_node->nodeType == $comment_node->COMMENT_NODE, 'nodeType == COMMENT_NODE');

# check texts + nodeType
my $text_node = $tree->createTextNode("text?");
can_ok($text_node, @node_methods);
ok(ref($text_node) eq 'HTML5::DOM::Text', 'check text ref');
ok($text_node->nodeType == $text_node->TEXT_NODE, 'nodeType == TEXT_NODE');

# check doctype + nodeType
my $doctype_node = $parser->parse('<!DOCTYPE html>')->document->[0];
can_ok($doctype_node, @node_methods);
ok(ref($doctype_node) eq 'HTML5::DOM::DocType', 'check doctype ref');
ok($doctype_node->nodeType == $doctype_node->DOCUMENT_TYPE_NODE, 'nodeType == DOCUMENT_TYPE_NODE');

# check fragment + nodeType
my $frag_node = $tree->parseFragment('test...');
can_ok($frag_node, @node_methods);
can_ok($frag_node, @element_methods);
ok(ref($frag_node) eq 'HTML5::DOM::Fragment', 'check fragment ref');
ok($frag_node->nodeType == $frag_node->DOCUMENT_FRAGMENT_NODE, 'nodeType == DOCUMENT_FRAGMENT_NODE');

# check document + nodeType
my $doc_node = $tree->document;
can_ok($doc_node, @node_methods);
can_ok($doc_node, @element_methods);
ok(ref($doc_node) eq 'HTML5::DOM::Document', 'check document ref');
ok($doc_node->nodeType == $doc_node->DOCUMENT_NODE, 'nodeType == DOCUMENT_NODE');

# tag + nodeName
$el_node = $tree->createElement("div");
ok($el_node->tag eq "div", "node->tag");
ok($el_node->nodeName eq "DIV", "node->nodeName");
ok($el_node->tagName eq "DIV", "node->tagName");

for my $method (qw|tag nodeName tagName|) {
	my $node = $tree->createElement("div");
	
	isa_ok($node->$method("span"), 'HTML5::DOM::Node');
	ok($node->nodeName eq "SPAN", "$method: change tag to span");
	
	isa_ok($node->$method("blablaxuj"), 'HTML5::DOM::Node');
	ok($node->nodeName eq "BLABLAXUJ", "$method: change tag to blablaxuj");
	
	isa_ok($node->$method("blablaxuj" x 102400), 'HTML5::DOM::Node');
	ok($node->nodeName eq "BLABLAXUJ" x 102400, "$method: change tag to long blablaxuj");
	
	eval { $node->$method(""); };
	ok($@ =~ /empty tag name not allowed/, "$method: change tag to empty string");
}

# tagId
$el_node = $tree->createElement("div");
ok($el_node->tagId == HTML5::DOM->TAG_DIV, "node->tagId");
isa_ok($el_node->tagId(HTML5::DOM->TAG_SPAN), 'HTML5::DOM::Node');
ok($el_node->tagId == HTML5::DOM->TAG_SPAN, "node->tagId");
eval { $el_node->tagId(9999999999999); };
ok($@ =~ /unknown tag id/, "tagId: change tag to unknown id");

# namespace
$el_node = $tree->createElement("div", "svg");
ok($el_node->namespace eq "SVG", "node->namespace");
isa_ok($el_node->namespace("hTml"), 'HTML5::DOM::Node');
ok($el_node->namespace eq "HTML", "node->namespace");
eval { $el_node->namespace("ewfwefwefwefwef"); };
ok($@ =~ /unknown namespace/, "node->namespace: set unknown namespace");

# namespaceId
$el_node = $tree->createElement("div");
ok($el_node->namespaceId == HTML5::DOM->NS_HTML, "node->namespaceId");
isa_ok($el_node->namespaceId(HTML5::DOM->NS_SVG), 'HTML5::DOM::Node');
ok($el_node->namespaceId == HTML5::DOM->NS_SVG, "node->namespaceId");
eval { $el_node->namespaceId(9999999999999); };
ok($@ =~ /unknown namespace/, "node->namespaceId: set unknown namespace");

# tree
isa_ok($el_node->tree, "HTML5::DOM::Tree");
ok($el_node->tree == $tree, "node->tree");

done_testing;
