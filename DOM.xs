#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <modest/finder/finder.h>
#include <myhtml/myhtml.h>
#include <myhtml/serialization.h>
#include <mycss/mycss.h>
#include <mycss/selectors/init.h>
#include <mycss/selectors/serialization.h>

#define node_is_element(node) (node->tag_id != MyHTML_TAG__UNDEF && node->tag_id != MyHTML_TAG__TEXT && node->tag_id != MyHTML_TAG__COMMENT && node->tag_id != MyHTML_TAG__DOCTYPE)

// #define DOM_GC_TRACE(msg, ...) fprintf(stderr, "[GC] " msg "\n", ##__VA_ARGS__);
#define DOM_GC_TRACE(...)

typedef struct {
	myhtml_t *myhtml;
	myhtml_tree_t *tree;
} html5_dom_parser_t;

typedef struct {
	SV *parser;
	SV *sv;
	myhtml_tree_t *tree;
} html5_dom_tree_t;

typedef html5_dom_parser_t *			HTML5__DOM;
typedef myhtml_collection_t *			HTML5__DOM__Collection;
typedef myhtml_tree_node_t *			HTML5__DOM__Node;
typedef html5_dom_tree_t *				HTML5__DOM__Tree;

static void html5_dom_parser_free(html5_dom_parser_t *self) {
	if (self->myhtml) {
		myhtml_destroy(self->myhtml);
		self->myhtml = NULL;
	}
}

static mystatus_t sv_serialization_callback(const char *data, size_t len, void *ctx) {
	sv_catpvn((SV *) ctx, data, len);
}

static inline SV *pack_pointer(const char *clazz, void *ptr) {
	SV *sv = newSV(0);
	sv_setref_pv(sv, clazz, ptr);
	return sv;
}

static void html5_dom_recursive_node_text(myhtml_tree_node_t *node, SV *sv) {
	node = myhtml_node_child(node);
	while (node) {
		if (node->tag_id == MyHTML_TAG__TEXT) {
			size_t text_len = 0;
			const char *text = myhtml_node_text(node, &text_len);
			if (text_len)
				sv_catpvn(sv, text, text_len);
		} else if (node_is_element(node)) {
			html5_dom_recursive_node_text(node, sv);
		}
		node = myhtml_node_next(node);
	}
}

static SV *create_tree_object(myhtml_tree_t *tree, SV *parser) {
	tree->context = malloc(sizeof(html5_dom_tree_t));
	
	html5_dom_tree_t *tree_obj = (html5_dom_tree_t *) tree->context;
	tree_obj->tree = tree;
	tree_obj->parser = parser;
	
	SvREFCNT_inc(parser);
	
	SV *sv = pack_pointer("HTML5::DOM::Tree", tree_obj);
	tree_obj->sv = SvRV(sv);
	
	DOM_GC_TRACE("DOM::Tree::NEW (refcnt=%d)", SvREFCNT(sv));
	
	return sv;
}

static SV *node_to_sv(myhtml_tree_node_t *node) {
	if (!node)
		return &PL_sv_undef;
	
	SV *sv = (SV *) myhtml_node_get_data(node);
	if (!sv) {
		SV *sv_ref = pack_pointer("HTML5::DOM::Node", (void *) node);
		sv = SvRV(sv_ref);
		myhtml_node_set_data(node, (void *) sv);
		
		DOM_GC_TRACE("DOM::Node::NEW (new refcnt=%d)", SvREFCNT(sv));
		
		html5_dom_tree_t *tree = (html5_dom_tree_t *) node->tree->context;
		SvREFCNT_inc(tree->sv);
		
		return sv_ref;
	} else {
		SV *sv_ref = newRV(sv);
		DOM_GC_TRACE("DOM::Node::NEW (reuse refcnt=%d)", SvREFCNT(sv));
		return sv_ref;
	}
}

static SV *collection_to_blessed_array(myhtml_collection_t *collection) {
	AV *arr = newAV();
	if (collection) {
		for (int i = 0; i < collection->length; ++i)
			av_push(arr, node_to_sv(collection->list[i]));
	}
	return sv_bless(newRV_noinc((SV *) arr), gv_stashpv("HTML5::DOM::Collection", 0));
}

static SV *sv_stringify(SV *sv) {
	if (SvROK(sv)) {
		SV *tmp_sv = SvRV(sv);
		if (SvOBJECT(tmp_sv)) {
			HV *stash = SvSTASH(tmp_sv);
			GV *to_string = gv_fetchmethod_autoload(stash, "\x28\x22\x22", 0);
			
			if (to_string) {
				dSP;
				ENTER; SAVETMPS; PUSHMARK(SP);
				XPUSHs(sv_bless(sv_2mortal(newRV_inc(tmp_sv)), stash));
				PUTBACK;
				call_sv((SV *) GvCV(to_string), G_SCALAR);
				SPAGAIN;
				
				SV *new_sv = POPs;
				
				PUTBACK;
				FREETMPS; LEAVE;
				
				return new_sv;
			}
		}
	}
	return sv;
}

MODULE = HTML5::DOM  PACKAGE = HTML5::DOM

HTML5::DOM
new(...)
CODE:
	DOM_GC_TRACE("DOM::new\n");
	
	mystatus_t status;
	
	html5_dom_parser_t *self = (html5_dom_parser_t *) malloc(sizeof(html5_dom_parser_t));
	memset(self, 0, sizeof(html5_dom_parser_t));
	
	self->myhtml = myhtml_create();
	status = myhtml_init(self->myhtml, MyHTML_OPTIONS_DEFAULT, 1, 0);
	if (status) {
		html5_dom_parser_free(self);
		croak("myhtml_init failed: %d", status);
	}
	
	RETVAL = self;
OUTPUT:
	RETVAL

# Parse html chunk
SV *
parseChunk(HTML5::DOM self, SV *html)
CODE:
	mystatus_t status;
	
	if (!self->tree) {
		self->tree = myhtml_tree_create();
		status = myhtml_tree_init(self->tree, self->myhtml);
		if (status) {
			myhtml_tree_destroy(self->tree);
			croak("myhtml_tree_init failed: %d", status);
		}
		myhtml_encoding_set(self->tree, MyENCODING_UTF_8);
	}
	
	STRLEN html_length;
	const char *html_str = SvPV_const(html, html_length);
	
	status = myhtml_parse_chunk(self->tree, html_str, html_length);
	if (status) {
		myhtml_tree_destroy(self->tree);
		croak("myhtml_parse_chunk failed: %d", status);
	}
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# End of parse chunks (return Tree)
SV *
parseChunkEnd(HTML5::DOM self)
CODE:
	mystatus_t status;
	
	if (!self->tree)
		croak("call parseChunk first");
	
	status = myhtml_parse_chunk_end(self->tree);
	if (status) {
		myhtml_tree_destroy(self->tree);
		croak("myhtml_parse_chunk failed: %d", status);
	}
	
	RETVAL = create_tree_object(self->tree, SvRV(ST(0)));
	self->tree = NULL;
OUTPUT:
	RETVAL

# Parse full html
SV *
parse(HTML5::DOM self, SV *html)
CODE:
	mystatus_t status;
	
	myhtml_tree_t *tree = myhtml_tree_create();
	status = myhtml_tree_init(tree, self->myhtml);
	if (status) {
		myhtml_tree_destroy(tree);
		croak("myhtml_tree_init failed: %d", status);
	}
	
	STRLEN html_length;
	const char *html_str = SvPV_const(html, html_length);
	
	status = myhtml_parse(tree, MyENCODING_UTF_8, html_str, html_length);
	if (status) {
		myhtml_tree_destroy(tree);
		croak("myhtml_parse failed: %d", status);
	}
	
	RETVAL = create_tree_object(tree, SvRV(ST(0)));
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM self)
CODE:
	DOM_GC_TRACE("DOM::DESTROY (refs=%d)\n", SvREFCNT(SvRV(ST(0))));
	html5_dom_parser_free(self);




MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::Tree

HTML5::DOM::Tree
new(...)
CODE:
	croak("no direct call, use parse methods");
OUTPUT:
	RETVAL



SV *
body(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_body(self->tree));
OUTPUT:
	RETVAL

SV *
head(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_head(self->tree));
OUTPUT:
	RETVAL

SV *
html(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_html(self->tree));
OUTPUT:
	RETVAL

SV *
document(HTML5::DOM::Tree self)
ALIAS:
	root = 1
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_html(self->tree));
OUTPUT:
	RETVAL

SV *
findTag(HTML5::DOM::Tree self, SV *tag)
CODE:
	tag = sv_stringify(tag);
	
	STRLEN tag_len;
	const char *tag_str = SvPV_const(tag, tag_len);
	
	myhtml_collection_t *collection = myhtml_get_nodes_by_name(self->tree, NULL, tag_str, tag_len, NULL);
	RETVAL = collection_to_blessed_array(collection);
	
	if (collection)
		myhtml_collection_destroy(collection);
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::Tree self)
CODE:
	DOM_GC_TRACE("DOM::Tree::DESTROY (refs=%d)\n", SvREFCNT(SvRV(ST(0))));
	void *context = self->tree->context;
	SvREFCNT_dec(self->parser);
	myhtml_tree_destroy(self->tree);
	free(context);



MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::Node
HTML5::DOM::Node
new(...)
CODE:
	croak("Can't manualy create node");
	RETVAL = NULL;
OUTPUT:
	RETVAL

# Tag id
int
tagId(HTML5::DOM::Node self)
CODE:
	RETVAL = self->tag_id;
OUTPUT:
	RETVAL

# Tag name
SV *
tag(HTML5::DOM::Node self)
CODE:
	myhtml_tree_t *tree = self->tree;
	
	RETVAL = &PL_sv_undef;
	
	if (tree && tree->tags) {
		const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_id(tree->tags, self->tag_id);
		if (tag_ctx)
			RETVAL = newSVpv(tag_ctx->name, tag_ctx->name_length);
	}
OUTPUT:
	RETVAL

# Serialize tree to html
SV *
html(HTML5::DOM::Node self, bool recursive = 1)
CODE:
	myhtml_tree_t *tree = self->tree;
	
	RETVAL = newSVpv("", 0);
	if (recursive) {
		myhtml_serialization_tree_callback(self, sv_serialization_callback, RETVAL);
	} else {
		myhtml_serialization_node_callback(self, sv_serialization_callback, RETVAL);
	}
OUTPUT:
	RETVAL

# Serialize tree to text
SV *
text(HTML5::DOM::Node self, bool recursive = 1)
CODE:
	myhtml_tree_t *tree = self->tree;
	
	RETVAL = newSVpv("", 0);
	if (recursive) {
		html5_dom_recursive_node_text(self, RETVAL);
	} else {
		myhtml_tree_node_t *node = myhtml_node_child(self);
		while (node) {
			if (node->tag_id == MyHTML_TAG__TEXT) {
				size_t text_len = 0;
				const char *text = myhtml_node_text(node, &text_len);
				if (text_len)
					sv_catpvn(RETVAL, text, text_len);
			}
			node = myhtml_node_next(node);
		}
	}
OUTPUT:
	RETVAL

# Next element
SV *
next(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *node = myhtml_node_next(self);
	while (node && !node_is_element(node))
		node = myhtml_node_next(node);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

# Next node
SV *
nextNode(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_node_next(self));
OUTPUT:
	RETVAL

# Prev element
SV *
prev(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *node = myhtml_node_prev(self);
	while (node && !node_is_element(node))
		node = myhtml_node_prev(node);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

# Prev node
SV *
prevNode(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_node_prev(self));
OUTPUT:
	RETVAL

# Parent node
SV *
parent(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_node_parent(self));
OUTPUT:
	RETVAL

# First child element
SV *
first(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *node = myhtml_node_child(self);
	while (node && !node_is_element(node))
		node = myhtml_node_next(node);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

# First child node
SV *
firstNode(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_node_child(self));
OUTPUT:
	RETVAL

# Last child element
SV *
last(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *node = myhtml_node_last_child(self);
	while (node && !node_is_element(node))
		node = myhtml_node_prev(node);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

# Last child node
SV *
lastNode(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_node_last_child(self));
OUTPUT:
	RETVAL

# attr()					- return all attributes in a hash
# attr("key")				- return value of attribute "key" (undef is not exists)
# attr("key", "value")		- set value for attribute "key" (return this)
# attr({"key" => "value"})	- bulk set value for attribute "key" (return this)
SV *
attr(HTML5::DOM::Node self, SV *key = NULL, SV *value = NULL)
CODE:
	RETVAL = &PL_sv_undef;
	
	if (key && value) { // Set value by key or delete by key
		key = sv_stringify(key);
		value = sv_stringify(value);
		
		STRLEN key_len = 0;
		const char *key_str = SvPV_const(key, key_len);
		
		if (key_len) {
			// if value is undef - only remove attribute
			myhtml_attribute_remove_by_key(self, key_str, key_len);
			if (SvTYPE(value) != SVt_NULL) {
				STRLEN val_len = 0;
				const char *val_str = SvPV_const(value, val_len);
				myhtml_attribute_add(self, key_str, key_len, val_str, val_len, self->tree->encoding);
			}
		}
		
		// return self
		RETVAL = SvREFCNT_inc(ST(0));
	} else if (key && !value) {
		// Bulk attr set
		if (SvROK(key) && SvTYPE(SvRV(key)) == SVt_PVHV) {
			HE *entry;
			HV *hash = (HV *) SvRV(key);
			
			while ((entry = hv_iternext(hash)) != NULL) {
				SV *value = hv_iterval(hash, entry);
				I32 key_len;
				const char *key_name = hv_iterkey(entry, &key_len);
				if (value && key_len) {
					value = sv_stringify(value);
					
					// if value is undef - only remove attribute
					myhtml_attribute_remove_by_key(self, key_name, key_len);
					if (SvTYPE(value) != SVt_NULL) {
						STRLEN val_len = 0;
						const char *val_str = SvPV_const(value, val_len);
						myhtml_attribute_add(self, key_name, key_len, val_str, val_len, self->tree->encoding);
					}
				}
			}
			
			RETVAL = SvREFCNT_inc(ST(0));
		}
		// Get attribute by key
		else {
			key = sv_stringify(key);
			
			STRLEN key_len = 0;
			const char *key_str = SvPV_const(key, key_len);
			
			if (key_len) {
				myhtml_tree_attr_t *attr = myhtml_attribute_by_key(self, key_str, key_len);
				if (attr) {
					size_t attr_val_len = 0;
					const char *attr_val = myhtml_attribute_value(attr, &attr_val_len);
					RETVAL = newSVpv(attr_val ? attr_val : "", attr_val_len);
				}
			}
		}
	} else { // Return all attributes in hash
		HV *hash = newHV();
		
		myhtml_tree_attr_t *attr = myhtml_node_attribute_first(self);
		while (attr) {
			size_t attr_key_len = 0;
			const char *attr_key = myhtml_attribute_key(attr, &attr_key_len);
			
			size_t attr_val_len = 0;
			const char *attr_val = myhtml_attribute_value(attr, &attr_val_len);
			
			hv_store_ent(hash, sv_2mortal(newSVpv(attr_key ? attr_key : "", attr_key_len)), newSVpv(attr_val ? attr_val : "", attr_val_len), 0);
			
			attr = myhtml_attribute_next(attr);
		}
		
		RETVAL = newRV_noinc((SV *) hash);
	}
OUTPUT:
	RETVAL

# Remove attribute by key
SV *
removeAttr(HTML5::DOM::Node self, SV *key = NULL)
CODE:
	key = sv_stringify(key);
	
	STRLEN key_len = 0;
	const char *key_str = SvPV_const(key, key_len);
	
	if (key_len)
		myhtml_attribute_remove_by_key(self, key_str, key_len);
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Flag if node is element
bool
isElement(HTML5::DOM::Node self)
CODE:
	RETVAL = node_is_element(self);
OUTPUT:
	RETVAL

# Return collection with children elements
SV *
children(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *child = myhtml_node_child(self);
	AV *arr = newAV();
	
	while (child) {
		if (node_is_element(child))
			av_push(arr, node_to_sv(child));
		child = myhtml_node_next(child);
	}
	
	RETVAL = sv_bless(newRV_noinc((SV *) arr), gv_stashpv("HTML5::DOM::Collection", 0));
OUTPUT:
	RETVAL

# Return collection with children nodes
SV *
childrenNode(HTML5::DOM::Node self)
CODE:
	myhtml_tree_node_t *child = myhtml_node_child(self);
	AV *arr = newAV();
	
	while (child) {
		av_push(arr, node_to_sv(child));
		child = myhtml_node_next(child);
	}
	
	RETVAL = sv_bless(newRV_noinc((SV *) arr), gv_stashpv("HTML5::DOM::Collection", 0));
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::Node self)
CODE:
	SV *sv = (SV *) myhtml_node_get_data(self);
	
	DOM_GC_TRACE("DOM::Node::DESTROY (refcnt=%d)\n", sv ? SvREFCNT(sv) : -666);
	
	if (sv) {
		html5_dom_tree_t *tree = (html5_dom_tree_t *) self->tree->context;
		SvREFCNT_dec(tree->sv);
		myhtml_node_set_data(self, NULL);
	}





