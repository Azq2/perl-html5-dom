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
	<div id="test0" some-attr="ololo trololo" class="red blue">
		<div class="yellow" id="test1"></div>
	</div>
	<div id="test2" some-attr="ololo" class="blue">
		<div class="yellow" id="test3"></div>
	</div>
');

# at
isa_ok($tree->at('div'), 'HTML5::DOM::Element');
ok($tree->at('div')->attr("id") eq 'test0', 'at');
ok(!defined $tree->at('xuj'), 'at not found');

# querySelector
isa_ok($tree->querySelector('div'), 'HTML5::DOM::Element');
ok($tree->querySelector('div')->attr("id") eq 'test0', 'at');
ok(!defined $tree->querySelector('xuj'), 'querySelector not found');

# findId
isa_ok($tree->findId('test2'), 'HTML5::DOM::Element');
ok($tree->findId('test2')->attr("id") eq 'test2', 'findId');
ok(!defined $tree->findId('xuj'), 'findId not found');

# getElementById
isa_ok($tree->getElementById('test2'), 'HTML5::DOM::Element');
ok($tree->getElementById('test2')->attr("id") eq 'test2', 'getElementById');
ok(!defined $tree->getElementById('xuj'), 'getElementById not found');

# find
isa_ok($tree->find('.blue'), 'HTML5::DOM::Collection');
isa_ok($tree->find('.ewfwefwefwefwef'), 'HTML5::DOM::Collection');
ok($tree->find('.blue')->length == 2, 'find results');
ok($tree->find('.ewfwefwefwefwef')->length == 0, 'find results not found');
ok($tree->find('.blue')->item(1)->attr("id") eq "test2", 'find #test2 by .blue');

# querySelectorAll
isa_ok($tree->querySelectorAll('.blue'), 'HTML5::DOM::Collection');
isa_ok($tree->querySelectorAll('.ewfwefwefwefwef'), 'HTML5::DOM::Collection');
ok($tree->querySelectorAll('.blue')->length == 2, 'querySelectorAll results');
ok($tree->querySelectorAll('.ewfwefwefwefwef')->length == 0, 'querySelectorAll results not found');
ok($tree->querySelectorAll('.blue')->item(1)->attr("id") eq "test2", 'querySelectorAll #test2 by .blue');

# findTag
isa_ok($tree->findTag('div'), 'HTML5::DOM::Collection');
isa_ok($tree->findTag('ewfwefwefwefwef'), 'HTML5::DOM::Collection');
ok($tree->findTag('div')->length == 4, 'findTag results');
ok($tree->findTag('ewfwefwefwefwef')->length == 0, 'findTag results not found');
ok($tree->findTag('div')->item(0)->attr("id") eq "test0", 'findTag #test0 by div');

# getElementsByTagName
isa_ok($tree->getElementsByTagName('div'), 'HTML5::DOM::Collection');
isa_ok($tree->getElementsByTagName('ewfwefwefwefwef'), 'HTML5::DOM::Collection');
ok($tree->getElementsByTagName('div')->length == 4, 'getElementsByTagName results');
ok($tree->getElementsByTagName('ewfwefwefwefwef')->length == 0, 'getElementsByTagName results not found');
ok($tree->getElementsByTagName('div')->item(0)->attr("id") eq "test0", 'getElementsByTagName #test0 by div');


done_testing;
