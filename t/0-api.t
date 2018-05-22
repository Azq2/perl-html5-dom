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
	html innerHTML outerHTML text innerText outerText textContent
	nodeHtml nodeValue data isConnected parent parentElement document ownerDocument
	append appendChild prepend prependChild replace replaceChild before insertBefore
	after insertAfter remove removeChild clone cloneNode void selfClosed position
	isSameNode wait parsed
);
my @element_methods = qw(
	first firstElementChild last lastElementChild firstNode firstChild lastNode lastChild
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

$tree = HTML5::DOM->new->parse('
   <ul>
       <li>Linux</li>
       <!-- comment -->
       <li>OSX</li>
       <li>Windows</li>
   </ul>
');

# test all siblings navigators
my $siblings_tests = [
	{
		methods	=> [qw|next nextElementSibling|], 
		index	=> 1, 
		results	=> [
			['HTML5::DOM::Element',	qr/^Linux$/], 
			['HTML5::DOM::Element',	qr/^OSX$/], 
			['HTML5::DOM::Element',	qr/^Windows$/], 
			['',					undef]
		]
	}, 
	{
		methods	=> [qw|prev previousElementSibling|], 
		index	=> -2, 
		results	=> [
			['HTML5::DOM::Element',	qr/^Windows$/], 
			['HTML5::DOM::Element',	qr/^OSX$/], 
			['HTML5::DOM::Element',	qr/^Linux$/], 
			['',					undef]
		]
	}, 
	{
		methods	=> [qw|nextNode nextSibling|], 
		index	=> 0, 
		results	=> [
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^Linux$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Comment',	qr/^ comment $/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^OSX$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^Windows$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['',					undef]
		]
	}, 
	{
		methods	=> [qw|prevNode previousSibling|], 
		index	=> -1, 
		results	=> [
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^Windows$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^OSX$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Comment',	qr/^ comment $/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['HTML5::DOM::Element',	qr/^Linux$/], 
			['HTML5::DOM::Text',	qr/^\s+$/], 
			['',					undef]
		]
	}
];

for my $test (@$siblings_tests) {
	my $ul = $tree->at('ul');
	ok($ul->tag eq 'ul', "siblings test: check test element");
	
	for my $method (@{$test->{methods}}) {
		my $next = $ul->childrenNode->[$test->{index}];
		my @chain = ($method);
		for my $result (@{$test->{results}}) {
			ok(ref($next) eq $result->[0], join(" > ", @chain)." check ref");
			
			if (defined $result->[1]) {
				ok($next->text =~ $result->[1], join(" > ", @chain)." check value");
			} else {
				ok(!defined $result->[1], join(" > ", @chain)." (undef)");
			}
			
			last if (!$next);
			
			$next = $next->$method;
			push @chain, $method;
		}
	}
}

$tree = HTML5::DOM->new->parse('
   <ul><!--
        first comment -->
       <li>Linux</li>
       <li>OSX</li>
       <li>Windows</li>
       <!-- last comment 
   --></ul>
');

# test all first/last navigators
my $first_last_tests = [
	{
		methods	=> [qw|first firstElementChild|], 
		results	=> [
			['HTML5::DOM::Element',	qr/^Linux$/], 
			['',					undef]
		]
	}, 
	{
		methods	=> [qw|last lastElementChild|], 
		results	=> [
			['HTML5::DOM::Element',	qr/^Windows$/], 
			['',					undef], 
		]
	}, 
	{
		methods	=> [qw|firstNode firstChild|], 
		results	=> [
			['HTML5::DOM::Comment',	qr/^\s+first comment\s+$/]
		]
	}, 
	{
		methods	=> [qw|lastNode lastChild|], 
		results	=> [
			['HTML5::DOM::Comment',	qr/^\s+last comment\s+$/]
		]
	}
];

for my $test (@$first_last_tests) {
	my $ul = $tree->at('ul');
	ok($ul->tag eq 'ul', "first/last test: check test element");
	
	for my $method (@{$test->{methods}}) {
		my $next = $ul->$method;
		my @chain = ($method);
		for my $result (@{$test->{results}}) {
			ok(ref($next) eq $result->[0], join(" > ", @chain)." check ref .. ".ref($next));
			
			if (defined $result->[1]) {
				ok($next->text =~ $result->[1], join(" > ", @chain)." check value");
			} else {
				ok(!defined $result->[1], join(" > ", @chain)." (undef)");
			}
			
			last if (!$next || !$next->can($method));
			
			$next = $next->$method;
			push @chain, $method;
		}
	}
}

# html and text serialzation
$tree = HTML5::DOM->new->parse('<body aaa="bb"><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b></body>');

my $html_serialize = {
	'html'			=> '<body aaa="bb"><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b></body>', 
	'innerHTML'		=> '<b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b>', 
	'outerHTML'		=> '<body aaa="bb"><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b></body>', 
	'nodeHtml'		=> '<body aaa="bb">', 
	'text'			=> '       ololo ???  ><"', 
	'innerText'		=> "ololo ???\n ><\"\n", 
	'outerText'		=> "ololo ???\n ><\"\n", 
	'textContent'	=> '       ololo ???  ><"', 
	'nodeValue'		=> undef, 
	'data'			=> undef
};

for my $method (keys %$html_serialize) {
	if (defined $html_serialize->{$method}) {
		ok($tree->body->$method eq $html_serialize->{$method}, "$method serialization");
	} else {
		ok(!defined $tree->body->$method, "$method serialization (undef)");
	}
}

# html/text fragments
my $html_serialize = [
	{
		method	=> 'html', 
		html	=> '<b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b>', 
		body	=> '<body><div id="test"><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b></div></body>'
	}, 
	{
		method	=> 'innerHTML', 
		html	=> '<b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b>', 
		body	=> '<body><div id="test"><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b></div></body>'
	}, 
	{
		method	=> 'outerHTML', 
		html	=> '<b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b>', 
		body	=> '<body><b>      <!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;"</div></b></body>'
	}, 
	{
		method	=> 'text', 
		html	=> "\nololo   >^_^<   trololo\n", 
		body	=> "<body><div id=\"test\">\nololo   &gt;^_^&lt;   trololo\n</div></body>"
	}, 
	{
		method	=> 'textContent', 
		html	=> "\nololo   >^_^<   trololo\n", 
		body	=> "<body><div id=\"test\">\nololo   &gt;^_^&lt;   trololo\n</div></body>"
	}, 
	{
		method	=> 'innerText', 
		html	=> "\nololo   >^_^<   trololo\n", 
		body	=> "<body><div id=\"test\"><br>ololo   &gt;^_^&lt;   trololo<br></div></body>"
	}, 
	{
		method	=> 'outerText', 
		html	=> "\nololo   >^_^<   trololo\n", 
		body	=> "<body><br>ololo   &gt;^_^&lt;   trololo<br></body>"
	}
];

for my $test (@$html_serialize) {
	$tree = HTML5::DOM->new->parse('<div id="test"><b><!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b></div>');
	
	my $method = $test->{method};
	my $method2 = $test->{method2};
	my $test_el = $tree->at('#test');
	
	my $ret = $test_el->$method($test->{html});
	isa_ok($ret, "HTML5::DOM::Node");
	ok($ret == $test_el, "$method return test: '".$tree->body->html."'");
	ok($tree->body->html eq $test->{body}, "$method content test");
}

# isConnected
my $node_test_connected = $tree->createElement('ololo');
ok($node_test_connected->isConnected == 0, 'isConnected == 0');
$tree->body->append($node_test_connected);
ok($node_test_connected->isConnected == 1, 'isConnected == 1');

# parent
for my $method (qw|parent parentElement|) {
	ok($node_test_connected->$method == $tree->body, "$method check");
}

# document + ownerDocument
for my $method (qw|document ownerDocument|) {
	ok($node_test_connected->$method == $tree->document, "$method check");
}

# clone
$tree = HTML5::DOM->new->parse('<div id="test"><b><!-- super cool new comment --> ololo ??? <div class="red">&nbsp;&gt;&lt;&quot;</div></b></div>');

my $clone_tests = [
	{
		src		=> $tree->at('#test'), 
		html	=> '<div id="test"></div>', 
		deep	=> 0
	}, 
	{
		src		=> $tree->at('#test'), 
		html	=> $tree->at('#test')->html, 
		deep	=> 1
	}, 
	{
		src		=> $tree->createComment(" comment >^_^< "), 
		html	=> $tree->createComment(" comment >^_^< ")->html, 
		deep	=> 0
	}, 
	{
		src		=> $tree->createComment(" comment >^_^< "), 
		html	=> $tree->createComment(" comment >^_^< ")->html, 
		deep	=> 1
	}, 
	{
		src		=> $tree->createTextNode(" text >^_^< "), 
		html	=> $tree->createTextNode(" text >^_^< ")->html, 
		deep	=> 0
	}, 
	{
		src		=> $tree->createTextNode(" text >^_^< "), 
		html	=> $tree->createTextNode(" text >^_^< ")->html, 
		deep	=> 1
	}, 
];

my $new_tree = HTML5::DOM->new->parse('<div id="test"></div>');

for my $copy_dst_tree (($tree, $new_tree)) {
	for my $method (qw|clone cloneNode|) {
		for my $test (@$clone_tests) {
			my $clone = $test->{src}->$method($test->{deep}, $copy_dst_tree);
			ok($copy_dst_tree == $clone->tree, ref($test->{src})."->$method(".$test->{deep}.") tree");
			ok($clone != $test->{src}, ref($test->{src})."->$method(".$test->{deep}.") eq");
			ok($clone->html eq $test->{html}, ref($test->{src})."$method(".$test->{deep}.") content");
		}
	}
}

# void
ok($tree->createElement('br')->void == 1, 'void == 1');
ok($tree->createElement('div')->void == 0, 'void == 0');

# selfClosed
ok($tree->parseFragment('<meta />')->first->selfClosed == 1, 'selfClosed == 1');
ok($tree->parseFragment('<meta></meta>')->first->selfClosed == 0, 'selfClosed == 0');

# wait
my $test_pos_buff = '<div><div id="position"></div></div>';
$tree = HTML5::DOM->new->parse($test_pos_buff);
isa_ok($tree->body->wait, "HTML5::DOM::Node");
ok($tree->body->parsed == 1, "parsed");

# position
my $pos = $tree->at('#position')->position;
ok(ref($pos) eq 'HASH', 'position is HASH');
ok(substr($test_pos_buff, $pos->{raw_begin}, $pos->{raw_length}) eq 'div', 'position raw begin/length');
ok(substr($test_pos_buff, $pos->{element_begin}, $pos->{element_length}) eq '<div id="position">', 'position element begin/length');

# isSameNode
ok($tree->body->isSameNode($tree->body) == 1, 'isSameNode == 1');
ok($tree->body->isSameNode($tree->head) == 0, 'isSameNode == 0');

done_testing;
