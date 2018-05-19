# NAME

HTML5::DOM - Super fast html5 DOM library with css selectors (based on Modest/MyHTML)

<div>
    <a href="https://travis-ci.org/Azq2/perl-html5-dom"><img src="https://travis-ci.org/Azq2/perl-html5-dom.svg?branch=master"></a>
</div>

# SYNOPSIS

# DESCRIPTION

[HTML5::DOM](https://metacpan.org/pod/HTML5::DOM) is a fast HTML5 parser and DOM manipulatin library with CSS4 selector, fully conformant with the HTML5 specification.

It based on  [https://github.com/lexborisov/Modest](https://github.com/lexborisov/Modest) as selector engine and [https://github.com/lexborisov/myhtml](https://github.com/lexborisov/myhtml) as HTML5 parser. 

# HTML5::DOM

HTML5 parser object.

## new

    # with default options
    my $parser = HTML5::DOM->new;
    
    # override some options, if you need
    my $parser = HTML5::DOM->new({
       threads             => 2,
       async               => 0, 
       ignore_whitespace   => 0, 
       ignore_doctype      => 0, 
       scripts             => 0, 
       encoding            => "auto", 
       default_encoding    => "UTF-8", 
       encoding_use_meta   => 1, 
       encoding_use_bom    => 1, 
    });

Creates new parser object with options. See ["PARSER OPTIONS"](#parseroptions) for details. 

### parse

    my $html = '<div>Hello world!</div>';
    
    # parsing with options defined in HTML5::DOM->new
    my $tree = $parser->parse($html);
    
    # parsing with custom options (extends options defined in HTML5::DOM->new)
    my $tree = $parser->parse($html, {
        scripts     => 0, 
    });

Parse html string and return [HTML5::DOM::Tree](#html5domtree) object.

### parseChunkStart

    # start chunked parsing with options defined in HTML5::DOM->new
    # call parseChunkStart without options is useless, 
    # because first call of parseChunk automatically call parseChunkStart. 
    $parser->parseChunkStart();
    
    # start chunked parsing with custom options (extends options defined in HTML5::DOM->new)
    $parser->parseChunkStart({
       scripts     => 0, 
    });

Init chunked parsing. See ["PARSER OPTIONS"](#parseroptions) for details. 

### parseChunk

    $parser->parseChunkStart()->parseChunk('<')->parseChunk('di')->parseChunk('v>');

Parse chunk of html stream.

### parseChunkEnd

    # start some chunked parsing
    $parser->parseChunk('<')->parseChunk('di')->parseChunk('v>');
    
    # end parsing and get tree
    my $tree = $parser->parseChunkEnd();

Completes chunked parsing and return [HTML5::DOM::Tree](#html5domtree) object.

# HTML5::DOM::Tree

DOM tree object.

### createElement

    # create new node with tag "div"
    my $node = $tree->createElement("div");
    
    # create new node with tag "g" with namespace "svg"
    my $node = $tree->createElement("div", "svg");

Create new [HTML5::DOM::Element](#html5domelement) with specified tag and namespace.

### createComment

    # create new comment
    my $node = $tree->createComment("ololo");
    
    print $node->html; # <!-- ololo -->

Create new [HTML5::DOM::Comment](#html5domcomment) with specified value.

### createTextNode

    # create new text node
    my $node = $tree->createTextNode("psh psh ololo i am driver of ufo >>>");
    
    print $node->html; # psh psh ololo i am driver of ufo &gt;&gt;&gt;

Create new [HTML5::DOM::Text](#html5domtext) with specified value.

### parseFragment

    my $fragment = $tree->parseFragment($html, $context = 'div', $context_ns = 'html', $options = {});

Parse fragment html and create new [HTML5::DOM::Fragment](#html5domfragment).
For more details about fragments: [https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments](https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments)

    # simple create new fragment
    my $node = $tree->parseFragment("some <b>bold</b> and <i>italic</i> text");

    # create new fragment node with custom context tag/namespace and options
    my $node = $tree->parseFragment("some <b>bold</b> and <i>italic</i> text", "div", "html", {
       # some options override
       encoding => "windows-1251"
    });
    
    print $node->html; # some <b>bold</b> and <i>italic</i> text

See ["PARSER OPTIONS"](#parseroptions) for details. 

### document

    my $node = $tree->document;

Return [HTML5::DOM::Document](#html5domdocument) node of current tree;

### root

    my $node = $tree->root;

Return root node of current tree. (always &lt;html>)

### head

    my $node = $tree->head;

Return &lt;head> node of current tree. 

### body

    my $node = $tree->body;

Return &lt;body> node of current tree. 

### at

### querySelector

    my $node = $tree->at($selector);
    my $node = $tree->querySelector($selector); # alias

Find one element node in tree using [CSS Selectors Level 4](https://www.w3.org/TR/selectors-4/)

Return node, or `undef` if not find.

- `$selector` - selector query as plain text or precompiled as [HTML5::DOM::CSS::Selector](#html5domcssselector) or 
[HTML5::DOM::CSS::Selector](#html5domcssselectorentry).

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $node = $tree->at('body > div.red');
    print $node->html; # <div class="red">red</div>

### find

### querySelectorAll

    my $collection = $tree->find($selector);
    my $collection = $tree->querySelectorAll($selector); # alias

Find all element nodes in tree using [CSS Selectors Level 4](https://www.w3.org/TR/selectors-4/)

Return [HTML5::DOM::Collection](#html5domcollection).

- `$selector` - selector query as plain text or precompiled as [HTML5::DOM::CSS::Selector](#html5domcssselector) or 
[HTML5::DOM::CSS::Selector](#html5domcssselectorentry).

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $collection = $tree->at('body > div.red, body > div.blue');
    print $collection->[0]->html; # <div class="red">red</div>
    print $collection->[1]->html; # <div class="red">blue</div>

### findId

### getElementById

    my $collection = $tree->findId($tag);
    my $collection = $tree->getElementById($tag); # alias

Find element node with specified id.

Return [HTML5::DOM::Node](#html5domnode) or `undef`.

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue" id="test">blue</div>')
    my $node = $tree->findId('test');
    print $node->html; # <div class="blue" id="test">blue</div>

### findTag

### getElementsByTagName

    my $collection = $tree->findTag($tag);
    my $collection = $tree->getElementsByTagName($tag); # alias

Find all element nodes in tree with specified tag name.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $collection = $tree->findTag('div');
    print $collection->[0]->html; # <div class="red">red</div>
    print $collection->[1]->html; # <div class="red">blue</div>

### findClass

### getElementsByClassName

    my $collection = $tree->findClass($class);
    my $collection = $tree->getElementsByClassName($class); # alias

Find all element nodes in tree with specified class name.
This is more fast equivalent to \[class~="value"\] selector.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new
       ->parse('<div class="red color">red</div><div class="blue color">blue</div>');
    my $collection = $tree->findClass('color');
    print $collection->[0]->html; # <div class="red color">red</div>
    print $collection->[1]->html; # <div class="red color">blue</div>

### findAttr

### getElementByAttribute

    # Find all elements with attribute
    my $collection = $tree->findAttr($attribute);
    my $collection = $tree->getElementByAttribute($attribute); # alias
    
    # Find all elements with attribute and mathcing value
    my $collection = $tree->findAttr($attribute, $value, $case = 0, $cmp = '=');
    my $collection = $tree->getElementByAttribute($attribute, $value, $case = 0, $cmp = '='); # alias

Find all element nodes in tree with specified attribute and optional matching value.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new
       ->parse('<div class="red color">red</div><div class="blue color">blue</div>');
    my $collection = $tree->findAttr('class', 'CoLoR', 1, '~');
    print $collection->[0]->html; # <div class="red color">red</div>
    print $collection->[1]->html; # <div class="red color">blue</div>
    

CSS selector analogs:

    # [$attribute=$value]
    my $collection = $tree->findAttr($attribute, $value, 0, '=');
    
    # [$attribute=$value i]
    my $collection = $tree->findAttr($attribute, $value, 1, '=');
    
    # [$attribute~=$value]
    my $collection = $tree->findAttr($attribute, $value, 0, '~');
    
    # [$attribute|=$value]
    my $collection = $tree->findAttr($attribute, $value, 0, '|');
    
    # [$attribute*=$value]
    my $collection = $tree->findAttr($attribute, $value, 0, '*');

### encoding

### encodingId

    print "encoding: ".$tree->encoding."\n"; # UTF-8
    print "encodingId: ".$tree->encodingId."\n"; # 0

Return current tree encoding. See ["ENCODINGS"](#encodings) for details. 

### tag2id

    print "tag id: ".HTML5::DOM::TAG_A."\n"; # tag id: 4
    print "tag id: ".$tree->tag2id("a")."\n"; # tag id: 4

Convert tag name to id. Return 0 (HTML5::DOM::TAG\_\_UNDEF), if tag not exists in tree.
See ["CONSTANTS"](#constants) for tag constants list. 

### id2tag

    print "tag name: ".$tree->id2tag(4)."\n"; # tag name: a
    print "tag name: ".$tree->id2tag(HTML5::DOM::TAG_A)."\n"; # tag name: a

Convert tag id to name. Return `undef`, if tag id not exists in tree.
See ["CONSTANTS"](#constants) for tag constants list. 

### namespace2id

    print "ns id: ".HTML5::DOM::NS_HTML."\n"; # ns id: 1
    print "ns id: ".$tree->namespace2id("html")."\n"; # ns id: 1

Convert namespace name to id. Return 0 (HTML5::DOM::NS\_UNDEF), if namespace not exists in tree.
See ["CONSTANTS"](#constants) for namespace constants list. 

### id2namespace

    print "ns name: ".$tree->id2namespace(1)."\n"; # ns name: html
    print "ns name: ".$tree->id2namespace(HTML5::DOM::NS_HTML)."\n"; # ns name: html

Convert namespace id to name. Return `undef`, if namespace id not exists.
See ["CONSTANTS"](#constants) for namespace constants list. 

### wait

    my $parser = HTML5::DOM->new({async => 1});
    my $tree = $parser->parse($some_big_html_file);
    # ...some your work...
    $tree->wait; # wait before parsing threads done

Blocking wait for tree parsing done. Only for async mode.

### parsed

    my $parser = HTML5::DOM->new({async => 1});
    my $tree = $parser->parse($some_big_html_file);
    # ...some your work...
    while (!$tree->parsed); # wait before parsing threads done

Non-blocking way for check if tree parsing done. Only for async mode.

### parser

    my $parser = $tree->parser;

Return parent [HTML5::DOM](#html5dom).

# HTML5::DOM::Node

DOM node object.

### tag

### nodeName

    my $tag_name = $node->tag;
    my $tag_name = $node->nodeName; # alias

Return node tag name (eg. div or span)

    $node->tag($tag);
    $node->nodeName($tag); # alias

Set new node tag name. Allow only for [HTML5::DOM::Element](#html5domelement) nodes.

    print $node->html; # <div></div>
    $node->tag('span');
    print $node->html; # <span></span>
    print $node->tag; # span

### tagId

    my $tag_id = $node->tagId;

Return node tag id. See ["CONSTANTS"](#constants) for tag constants list.

    $node->tagId($tag_id);

Set new node tag id. Allow only for [HTML5::DOM::Element](#html5domelement) nodes.

    print $node->html; # <div></div>
    $node->tagId(HTML5::DOM::TAG_SPAN);
    print $node->html; # <span></span>
    print $node->tagId; # 117

### namespace

    my $tag_ns = $node->namespace;

Return node namespace (eg. html or svg)

    $node->namespace($namespace);

Set new node namespace name. Allow only for [HTML5::DOM::Element](#html5domelement) nodes.

    print $node->namespace; # html
    $node->namespace('svg');
    print $node->namespace; # svg

### namespaceId

    my $tag_ns_id = $node->namespaceId;

Return node namespace id. See ["CONSTANTS"](#constants) for tag constants list.

    $node->namespaceId($tag_id);

Set new node namespace by id. Allow only for [HTML5::DOM::Element](#html5domelement) nodes.

    print $node->namespace; # html
    $node->namespaceId(HTML5::DOM::NS_SVG);
    print $node->namespaceId; # 3
    print $node->namespace; # svg

### tree

    my $tree = $node->tree;
    

Return parent [HTML5::DOM::Tree](#html5domtree).

### nodeType

    my $type = $node->nodeType;
    

Return node type. All types:

    HTML5::DOM::ELEMENT_NODE                   => 1, 
    HTML5::DOM::ATTRIBUTE_NODE                 => 2,   # not supported
    HTML5::DOM::TEXT_NODE                      => 3, 
    HTML5::DOM::CDATA_SECTION_NODE             => 4,   # not supported
    HTML5::DOM::ENTITY_REFERENCE_NODE          => 5,   # not supported
    HTML5::DOM::ENTITY_NODE                    => 6,   # not supported
    HTML5::DOM::PROCESSING_INSTRUCTION_NODE    => 7,   # not supported
    HTML5::DOM::COMMENT_NODE                   => 8, 
    HTML5::DOM::DOCUMENT_NODE                  => 9, 
    HTML5::DOM::DOCUMENT_TYPE_NODE             => 10, 
    HTML5::DOM::DOCUMENT_FRAGMENT_NODE         => 11, 
    HTML5::DOM::NOTATION_NODE                  => 12   # not supported

Compatible with: [https://developer.mozilla.org/ru/docs/Web/API/Node/nodeType](https://developer.mozilla.org/ru/docs/Web/API/Node/nodeType)

### next

### nextElementSibling

    my $node2 = $node->next;
    my $node2 = $node->nextElementSibling; # alias

Return next sibling element node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <!-- comment -->
           <li>OSX</li>
           <li>Windows</li>
       </ul>
    ');
    my $li = $tree->at('ul li');
    print $li->text;               # Linux
    print $li->next->text;         # OSX
    print $li->next->next->text;   # Windows

### prev

### previousElementSibling

    my $node2 = $node->prev;
    my $node2 = $node->previousElementSibling; # alias

Return previous sibling element node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <!-- comment -->
           <li>OSX</li>
           <li class="win">Windows</li>
       </ul>
    ');
    my $li = $tree->at('ul li.win');
    print $li->text;               # Windows
    print $li->prev->text;         # OSX
    print $li->prev->prev->text;   # Linux

### nextNode

### nextSibling

    my $node2 = $node->nextNode;
    my $node2 = $node->nextSibling; # alias

Return next sibling node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <!-- comment -->
           <li>OSX</li>
           <li>Windows</li>
       </ul>
    ');
    my $li = $tree->at('ul li');
    print $li->text;                       # Linux
    print $li->nextNode->text;             # <!-- comment -->
    print $li->nextNode->nextNode->text;   # OSX

### prevNode

### previousSibling

    my $node2 = $node->prevNode;
    my $node2 = $node->previousSibling; # alias

Return previous sibling node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <!-- comment -->
           <li>OSX</li>
           <li class="win">Windows</li>
       </ul>
    ');
    my $li = $tree->at('ul li.win');
    print $li->text;                       # Windows
    print $li->prevNode->text;             # OSX
    print $li->prevNode->prevNode->text;   # <!-- comment -->

### first

### firstElementChild

    my $node2 = $node->first;
    my $node2 = $node->firstElementChild; # alias

Return first children element

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <!-- comment -->
           <li>Linux</li>
           <li>OSX</li>
           <li class="win">Windows</li>
       </ul>
    ');
    my $ul = $tree->at('ul');
    print $ul->first->text; # Linux

### last

### lastElementChild

    my $node2 = $node->last;
    my $node2 = $node->lastElementChild; # alias

Return last children element

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <li>OSX</li>
           <li class="win">Windows</li>
           <!-- comment -->
       </ul>
    ');
    my $ul = $tree->at('ul');
    print $ul->last->text; # Windows

### firstNode

### firstChild

    my $node2 = $node->firstNode;
    my $node2 = $node->firstChild; # alias

Return first children node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <!-- comment -->
           <li>Linux</li>
           <li>OSX</li>
           <li class="win">Windows</li>
       </ul>
    ');
    my $ul = $tree->at('ul');
    print $ul->firstNode->html; # <!-- comment -->

### lastNode

### lastChild

    my $node2 = $node->lastNode;
    my $node2 = $node->lastChild; # alias

Return last children node

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>Linux</li>
           <li>OSX</li>
           <li class="win">Windows</li>
           <!-- comment -->
       </ul>
    ');
    my $ul = $tree->at('ul');
    print $ul->lastNode->html; # <!-- comment -->

### html

Universal html serialization and fragment parsing acessor, for single human-friendly api.

    my $html = $node->html();
    my $node = $node->html($new_html);

- As getter this similar to [outerText](#outertext)
- As setter this similar to [innerText](#innertext)
- As setter for non-element nodes this similar to [nodeValue](#nodevalue)

    my $tree = HTML5::DOM->new->parse('<div id="test">some   text <b>bold</b></div>');
    
    # get text content for element
    my $node = $tree->at('#test');
    print $node->html;                     # <div id="test">some   text <b>bold</b></div>
    $comment->html('<b>new</b>');
    print $comment->html;                  # <div id="test"><b>new</b></div>
    
    my $comment = $tree->createComment("comment text");
    print $comment->html;                  # <!-- comment text -->
    $comment->html('new comment text');
    print $comment->html;                  # <!-- new comment text -->
    
    my $text_node = $tree->createTextNode("plain text >");
    print $text_node->html;                # plain text &gt;
    $text_node->html('new>plain>text');
    print $text_node->html;                # new&gt;plain&gt;text

### innerHTML

### outerHTML

- HTML serialization of the node's descendants. 

        my $html = $node->html;
        my $html = $node->outerHTML;

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
        print $tree->outerHTML;                         # <div id="test">some <b>bold</b> test</div>
        print $tree->createComment('test')->outerHTML;  # <!-- test -->
        print $tree->createTextNode('test')->outerHTML; # test

- HTML serialization of the node and its descendants.

        # serialize descendants, without node
        my $html = $node->innerHTML;

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
        print $tree->innerHTML;                         # some <b>bold</b> test
        print $tree->createComment('test')->innerHTML;  # <!-- test -->
        print $tree->createTextNode('test')->innerHTML; # test

- Removes all of the element's descendants and replaces them with nodes constructed by parsing the HTML given in the string **$new\_html**.

        # parse fragment and replace child nodes with it
        my $html = $node->html($new_html);
        my $html = $node->innerHTML($new_html);

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
        print $tree->at('#test')->innerHTML('<i>italic</i>');
        print $tree->body->innerHTML;  # <div id="test"><i>italic</i></div>

- Replaces the element and all of its descendants with a new DOM tree constructed by parsing the specified **$new\_html**.

        # parse fragment and node in parent node childs with it
        my $html = $node->outerHTML($new_html);

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
        print $tree->at('#test')->outerHTML('<i>italic</i>');
        print $tree->body->innerHTML;  # <i>italic</i>

See, for more info:

[https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML](https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML)

[https://developer.mozilla.org/en-US/docs/Web/API/Element/outerHTML](https://developer.mozilla.org/en-US/docs/Web/API/Element/outerHTML)

### text

Universal text acessor, for single human-friendly api. 

    my $text = $node->text();
    my $node = $node->text($new_text);

- For [HTML5::DOM::Text](#html5domtext) is similar to [nodeValue](#nodevalue) (as setter/getter)
- For [HTML5::DOM::Comment](#html5domcomment) is similar to [nodeValue](#nodevalue) (as setter/getter)
- For [HTML5::DOM::DocType](#html5domdoctype) is similar to [nodeValue](#nodevalue) (as setter/getter)
- For [HTML5::DOM::Element](#html5domelement) is similar to [textContent](#textcontent) (as setter/getter)

    my $tree = HTML5::DOM->new->parse('<div id="test">some   text <b>bold</b></div>');
    
    # get text content for element
    my $node = $tree->at('#test');
    print $node->text;                     # some   text bold
    $comment->text('<new node content>');
    print $comment->html;                  # &lt;new node conten&gt;
    
    my $comment = $tree->createComment("comment text");
    print $comment->text;                  # comment text
    $comment->text('new comment text');
    print $comment->html;                  # <!-- new comment text -->
    
    my $text_node = $tree->createTextNode("plain text");
    print $text_node->text;                # plain text
    $text_node->text('new>plain>text');
    print $text_node->html;                # new&gt;plain&gt;text

### innerText

### outerText

### textContent

- Represents the "rendered" text content of a node and its descendants. 
Using default CSS "display" property for tags based on Firefox user-agent style. 

    Only works for elements, for other nodes return `undef`.

        my $text = $node->innerText;
        my $text = $node->outerText; # alias

    Example:

        my $tree = HTML5::DOM->new->parse('
           <div id="test">
               some       
               <b>      bold     </b>       
               test
               <script>alert()</script>
           </div>
        ');
        print $tree->body->innerText; # some bold test

    See, for more info: [https://html.spec.whatwg.org/multipage/dom.html#the-innertext-idl-attribute](https://html.spec.whatwg.org/multipage/dom.html#the-innertext-idl-attribute)

- Removes all of its children and replaces them with a text nodes and &lt;br> with the given value.
Only works for elements, for other nodes throws exception.

    - All new line chars (\\r\\n, \\r, \\n) replaces to &lt;br />
    - All other text content replaces to text nodes

        my $node = $node->innerText($text);

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some text <b>bold</b></div>');
        $tree->at('#test')->innerText("some\nnew\ntext >");
        print $tree->at('#test')->html;    # <div id="test">some<br />new<br />text &gt;</div>

    See, for more info: [https://html.spec.whatwg.org/multipage/dom.html#the-innertext-idl-attribute](https://html.spec.whatwg.org/multipage/dom.html#the-innertext-idl-attribute)

- Removes the current node and replaces it with the given text.
Only works for elements, for other nodes throws exception.

    - All new line chars (\\r\\n, \\r, \\n) replaces to &lt;br />
    - All other text content replaces to text nodes
    - Similar to innerText($text), but removes current node

        my $node = $node->outerText($text);

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some text <b>bold</b></div>');
        $tree->at('#test')->outerText("some\nnew\ntext >");
        print $tree->body->html;   # <body>some<br />new<br />text &gt;</body>

    See, for more info: [https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/outerText](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/outerText)

- Represents the text content of a node and its descendants.

    Only works for elements, for other nodes return `undef`.

        my $text = $node->text;
        my $text = $node->textContent; # alias

    Example:

        my $tree = HTML5::DOM->new->parse('<b>    test      </b><script>alert()</script>');
        print $tree->body->text; #     test      alert()

    See, for more info: [https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent](https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent)

- Removes all of its children and replaces them with a single text node with the given value.

        my $node = $node->text($new_text);
        my $node = $node->textContent($new_text);

    Example:

        my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
        print $tree->at('#test')->text('<bla bla bla>');
        print $tree->at('#test')->html;  # <div id="test">&lt;bla bla bla&gt;</div>

    See, for more info: [https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent](https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent)

### nodeHtml

    my $html = $node->nodeHtml();

Serialize to html, without descendants and closing tag.

    my $tree = HTML5::DOM->new->parse('<div id="test">some <b>bold</b> test</div>');
    print $tree->at('#test')->nodeHtml(); # <div id="test">

### nodeValue

### data

    my $value = $node->nodeValue();
    my $value = $node->data(); # alias

    my $node = $node->nodeValue($new_value);
    my $node = $node->data($new_value); # alias

Get or set value of node. Only works for non-element nodes, such as  [HTML5::DOM::Element](#html5domtext),  [HTML5::DOM::Element](#html5domdoctype), 
[HTML5::DOM::Element](#html5domcomment). Return `undef` for other.

    my $tree = HTML5::DOM->new->parse('');
    my $comment = $tree->createComment("comment text");
    print $comment->nodeValue;                 # comment text
    $comment->nodeValue('new comment text');
    print $comment->html;                      # <!-- new comment text -->

### isConnected

    my $flag = $node->isConnected;

Return true, if node has parent.

    my $tree = HTML5::DOM->new->parse('
       <div id="test"></div>
    ');
    print $tree->at('#test')->isConnected;             # 1
    print $tree->createElement("div")->isConnected;    # 0

### parent

### parentElement

    my $node = $node->parent;
    my $node = $node->parentElement; # alias

Return parent node. Return `undef`, if node detached.

    my $tree = HTML5::DOM->new->parse('
       <div id="test"></div>
    ');
    print $tree->at('#test')->parent->tag; # body

### document

### ownerDocument

    my $doc = $node->document;
    my $doc = $node->ownerDocument; # alias

Return parent [HTML5::DOM::Document](#html5domdocument). 

    my $tree = HTML5::DOM->new->parse('
       <div id="test"></div>
    ');
    print ref($tree->at('#test')->document);   # HTML5::DOM::Document

### append

### appendChild

    my $node = $node->append($child);
    my $child = $node->appendChild($child); # alias

Append node to child nodes.

**append** - returned value is the self node, for chain calls

**appendChild** - returned value is the appended child except when the given child is a [HTML5::DOM::Fragment](#html5domfragment), 
in which case the empty [HTML5::DOM::Fragment](#html5domfragment) is returned.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    $tree->at('div')
       ->append($tree->createElement('br'))
       ->append($tree->createElement('br'));
    print $tree->at('div')->html; # <div>some <b>bold</b> text<br /><br /></div>

### prepend

### prependChild

    my $node = $node->prepend($child);
    my $child = $node->prependChild($child); # alias

Prepend node to child nodes.

**prepend** - returned value is the self node, for chain calls

**prependChild** - returned value is the prepended child except when the given child is a [HTML5::DOM::Fragment](#html5domfragment), 
in which case the empty [HTML5::DOM::Fragment](#html5domfragment) is returned.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    $tree->at('div')
       ->prepend($tree->createElement('br'))
       ->prepend($tree->createElement('br'));
    print $tree->at('div')->html; # <div><br /><br />some <b>bold</b> text</div>

### replace

### replaceChild

    my $old_node = $old_node->replace($new_node);
    my $old_node = $old_node->parent->replaceChild($old_node, $new_node); # alias

Replace node in parent child nodes.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    my $old = $tree->at('b')->replace($tree->createElement('br'));
    print $old->html;              # <b>bold</b>
    print $tree->at('div')->html;  # <div>some <br /> text</div>

### before

### insertBefore

    my $node = $node->before($new_node);
    my $new_node = $node->parent->insertBefore($new_node, $node); # alias

Insert new node before current node.

**before** - returned value is the self node, for chain calls

**insertBefore** - returned value is the added child except when the given child is a [HTML5::DOM::Fragment](#html5domfragment), 
in which case the empty [HTML5::DOM::Fragment](#html5domfragment) is returned.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    $tree->at('b')->before($tree->createElement('br'));
    print $tree->at('div')->html; # <div>some <br /><b>bold</b> text</div>

### after

### insertAfter

    my $node = $node->after($new_node);
    my $new_node = $node->parent->insertAfter($new_node, $node); # alias

Insert new node after current node.

**after** - returned value is the self node, for chain calls

**insertAfter** - returned value is the added child except when the given child is a [HTML5::DOM::Fragment](#html5domfragment), 
in which case the empty [HTML5::DOM::Fragment](#html5domfragment) is returned.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    $tree->at('b')->after($tree->createElement('br'));
    print $tree->at('div')->html; # <div>some <b>bold</b><br /> text</div>

### remove

### removeChild

    my $node = $node->remove;
    my $node = $node->parent->removeChild($node); # alias

Remove node from parent. Return removed node.

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    print $tree->at('b')->remove->html;    # <b>bold</b>
    print $tree->at('div')->html;          # <div>some  text</div>

### clone

### cloneNode

    # clone node to current tree
    my $node = $node->clone($deep = 0);
    my $node = $node->cloneNode($deep = 0); # alias

    # clone node to foreign tree
    my $node = $node->clone($deep, $new_tree);
    my $node = $node->cloneNode($deep, $new_tree); # alias

Clone node. 

**deep** = 0 - only specified node, without childs. 

**deep** = 1 - deep copy with all child nodes.

**new\_tree** - destination tree (if need copy to foreign tree)

    my $tree = HTML5::DOM->new->parse('
       <div>some <b>bold</b> text</div>
    ');
    print $tree->at('b')->clone(0)->html; # <b></b>
    print $tree->at('b')->clone(1)->html; # <b>bold</b>

### void

    my $flag = $node->void;

Return true if node is void. For more details: [http://w3c.github.io/html-reference/syntax.html#void-elements](http://w3c.github.io/html-reference/syntax.html#void-elements)

    print $tree->createElement('br')->void; # 1

### selfClosed

    my $flag = $node->selfClosed;

Return true if node self closed. 

    print $tree->createElement('br')->selfClosed; # 1

### position

    my $position = $node->position;

Return offsets in input buffer.

    print Dumper($node->position);
    # $VAR1 = {'raw_length' => 3, 'raw_begin' => 144, 'element_begin' => 143, 'element_length' => 5}

### isSameNode

    my $flag = $node->isSameNode($other_node);

Tests whether two nodes are the same, that is if they reference the same object.

    my $tree = HTML5::DOM->new->parse('
       <ul>
           <li>test</li>
           <li>not test</li>
           <li>test</li>
       </ul>
    ');
    my $li = $tree->find('li');
    print $li->[0]->isSameNode($li->[0]); # 1
    print $li->[0]->isSameNode($li->[1]); # 0
    print $li->[0]->isSameNode($li->[2]); # 0

### wait

    my $parser = HTML5::DOM->new({async => 1});
    my $tree = $parser->parse($some_big_html_file);
    # ...some your work...
    $tree->body->wait; # wait before parsing for <body> is done

Blocking wait for node parsing done. Only for async mode.

### parsed

    my $parser = HTML5::DOM->new({async => 1});
    my $tree = $parser->parse($some_big_html_file);
    # ...some your work...
    while (!$tree->body->parsed); # wait before parsing for <body> is done

Non-blocking way for check if node parsing done. Only for async mode.

# HTML5::DOM::Element

DOM node object for elements. Inherit all methods from [HTML5::DOM::Node](#html5domnode).

### at

### querySelector

    my $node = $node->at($selector);
    my $node = $node->at($selector, $combinator);
    my $node = $node->querySelector($selector); # alias
    my $node = $node->querySelector($selector, $combinator); # alias

Find one element node in current node descendants using [CSS Selectors Level 4](https://www.w3.org/TR/selectors-4/)

Return node, or `undef` if not find.

- `$selector` - selector query as plain text or precompiled as [HTML5::DOM::CSS::Selector](#html5domcssselector) or 
[HTML5::DOM::CSS::Selector](#html5domcssselectorentry).
- `$combinator` - custom selector combinator, applies to current node
    - `>>` - descendant selector (default)
    - `>` - child selector
    - `+` - adjacent sibling selector
    - `~` - general sibling selector
    - `||` - column combinator

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $node = $tree->body->at('body > div.red');
    print $node->html; # <div class="red">red</div>

### find

### querySelectorAll

    my $collection = $node->find($selector);
    my $collection = $node->find($selector, $combinator);
    my $collection = $node->querySelectorAll($selector); # alias
    my $collection = $node->querySelectorAll($selector, $combinator); # alias

Find all element nodes in current node descendants using [CSS Selectors Level 4](https://www.w3.org/TR/selectors-4/)

Return [HTML5::DOM::Collection](#html5domcollection).

- `$selector` - selector query as plain text or precompiled as [HTML5::DOM::CSS::Selector](#html5domcssselector) or 
[HTML5::DOM::CSS::Selector](#html5domcssselectorentry).
- `$combinator` - custom selector combinator, applies to current node
    - `>>` - descendant selector (default)
    - `>` - child selector
    - `+` - adjacent sibling selector
    - `~` - general sibling selector
    - `||` - column combinator

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $collection = $tree->body->at('body > div.red, body > div.blue');
    print $collection->[0]->html; # <div class="red">red</div>
    print $collection->[1]->html; # <div class="red">blue</div>

### findId

### getElementById

    my $node = $node->findId($tag);
    my $node = $node->getElementById($tag); # alias

Find element node with specified id in current node descendants.

Return [HTML5::DOM::Node](#html5domnode) or `undef`.

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue" id="test">blue</div>')
    my $node = $tree->body->findId('test');
    print $node->html; # <div class="blue" id="test">blue</div>

### findTag

### getElementsByTagName

    my $node = $node->findTag($tag);
    my $node = $node->getElementsByTagName($tag); # alias

Find all element nodes in current node descendants with specified tag name.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new->parse('<div class="red">red</div><div class="blue">blue</div>')
    my $collection = $tree->body->findTag('div');
    print $collection->[0]->html; # <div class="red">red</div>
    print $collection->[1]->html; # <div class="red">blue</div>

### findClass

### getElementsByClassName

    my $collection = $node->findClass($class);
    my $collection = $node->getElementsByClassName($class); # alias

Find all element nodes in current node descendants with specified class name.
This is more fast equivalent to \[class~="value"\] selector.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new
       ->parse('<div class="red color">red</div><div class="blue color">blue</div>');
    my $collection = $tree->body->findClass('color');
    print $collection->[0]->html; # <div class="red color">red</div>
    print $collection->[1]->html; # <div class="red color">blue</div>

### findAttr

### getElementByAttribute

    # Find all elements with attribute
    my $collection = $node->findAttr($attribute);
    my $collection = $node->getElementByAttribute($attribute); # alias
    
    # Find all elements with attribute and mathcing value
    my $collection = $node->findAttr($attribute, $value, $case = 0, $cmp = '=');
    my $collection = $node->getElementByAttribute($attribute, $value, $case = 0, $cmp = '='); # alias

Find all element nodes in tree with specified attribute and optional matching value.

Return [HTML5::DOM::Collection](#html5domcollection).

    my $tree = HTML5::DOM->new
       ->parse('<div class="red color">red</div><div class="blue color">blue</div>');
    my $collection = $tree->body->findAttr('class', 'CoLoR', 1, '~');
    print $collection->[0]->html; # <div class="red color">red</div>
    print $collection->[1]->html; # <div class="red color">blue</div>
    

CSS selector analogs:

    # [$attribute=$value]
    my $collection = $node->findAttr($attribute, $value, 0, '=');
    
    # [$attribute=$value i]
    my $collection = $node->findAttr($attribute, $value, 1, '=');
    
    # [$attribute~=$value]
    my $collection = $node->findAttr($attribute, $value, 0, '~');
    
    # [$attribute|=$value]
    my $collection = $node->findAttr($attribute, $value, 0, '|');
    
    # [$attribute*=$value]
    my $collection = $node->findAttr($attribute, $value, 0, '*');

# HTML5::DOM::Document

DOM node object for document. Inherit all methods from [HTML5::DOM::Element](#html5domelement).

# HTML5::DOM::Fragment

DOM node object for fragments. Inherit all methods from [HTML5::DOM::Element](#html5domelement).

# HTML5::DOM::Text

DOM node object for text. Inherit all methods from [HTML5::DOM::Node](#html5domnode).

# HTML5::DOM::Comment

DOM node object for comments. Inherit all methods from [HTML5::DOM::Node](#html5domnode).

# HTML5::DOM::DocType

DOM node object for document type. Inherit all methods from [HTML5::DOM::Node](#html5domnode).

# PARSER OPTIONS

Options for [HTML5::DOM::new](https://metacpan.org/pod/HTML5::DOM::new), [HTML5::DOM::parse](https://metacpan.org/pod/HTML5::DOM::parse), [HTML5::DOM::new](https://metacpan.org/pod/HTML5::DOM::new), [HTML5::DOM::Node::parseFragment](https://metacpan.org/pod/HTML5::DOM::Node::parseFragment)

#### threads

Threads count, if 0 - parsing in single mode without threads (default 2)

#### async

If async 0 (default), then some parse functions [HTML5::DOM::Node::parseFragment](#parsefragment), [HTML5::DOM::parse](#parse), [HTML5::DOM::parseChunkEnd](#parsechunkend) waiting for parsing done.

If async 1, you must manualy call [HTML5::DOM::Node::wait](#wait) and [HTML5::DOM::Tree::wait](#wait) for waiting parsing of node or tree done or 
[HTML5::DOM::Node::parsed](#parsed), [HTML5::DOM::Node::parsed](#parsed) to non-blocking determine parsing done.

This options affects only if threads > 0

#### ignore\_whitespace

Ignore whitespace tokens (default 0)

#### ignore\_doctype

Do not parse DOCTYPE (default 0)

#### scripts

If 1 - &lt;noscript> contents parsed to single text node (default)

If 0 - &lt;noscript> contents parsed to child nodes

#### encoding

Encoding of input HTML, if auto - library can tree to automaticaly determine encoding. (default "auto")

#### default\_encoding

Default encoding, this affects only if encoding set to "auto" and encoding not determined. (default "UTF-8")

#### encoding\_use\_meta

Allow use &lt;meta> tags to determine input HTML encoding. (default 1)

#### encoding\_use\_bom

Allow use detecding BOM to determine input HTML encoding. (default 1)
