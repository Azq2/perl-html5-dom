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

#define sub_croak(cv, msg, ...) do { \
	const GV *const __gv = CvGV(cv); \
	if (__gv) { \
		const char *__gvname = GvNAME(__gv); \
		const HV *__stash = GvSTASH(__gv); \
		const char *__hvname = __stash ? HvNAME(__stash) : NULL; \
		Perl_croak_nocontext("%s%s%s(): " msg, __hvname ? __hvname : __gvname, __hvname ? "::" : "", __hvname ? __gvname : "", ##__VA_ARGS__); \
	} \
} while (0);

typedef struct {
	myhtml_t *myhtml;
	myhtml_tree_t *tree;
	mycss_t *mycss;
	mycss_entry_t *mycss_entry;
	modest_finder_t *finder;
} html5_dom_parser_t;

typedef struct {
	SV *parent;
	SV *sv;
	myhtml_tree_t *tree;
	html5_dom_parser_t *parser;
} html5_dom_tree_t;

typedef struct {
	mycss_t *mycss;
	mycss_entry_t *entry;
	myencoding_t encoding;
} html5_css_parser_t;

typedef struct {
	html5_css_parser_t *parser;
	mycss_selectors_list_t *list;
	SV *parent;
} html5_css_selector_t;

typedef struct {
	html5_css_parser_t *parser;
	mycss_selectors_entries_list_t *list;
	SV *parent;
} html5_css_selector_entry_t;

typedef html5_dom_parser_t *			HTML5__DOM;
typedef myhtml_collection_t *			HTML5__DOM__Collection;
typedef myhtml_tree_node_t *			HTML5__DOM__Node;
typedef html5_dom_tree_t *				HTML5__DOM__Tree;
typedef html5_css_parser_t *			HTML5__DOM__CSS;
typedef html5_css_selector_t *			HTML5__DOM__CSS__Selector;
typedef html5_css_selector_entry_t *	HTML5__DOM__CSS__Selector__Entry;

static const char *modest_strerror(mystatus_t status) {
	switch (status) {
		#include "modest_errors.c"	
	}
	return status ? "UNKNOWN" : "";
}

static void html5_dom_parser_free(html5_dom_parser_t *self) {
	if (self->myhtml) {
		myhtml_destroy(self->myhtml);
		self->myhtml = NULL;
	}
	
	if (self->mycss_entry) {
		mycss_entry_destroy(self->mycss_entry, 1);
		self->mycss_entry = NULL;
	}
	
	if (self->mycss) {
		mycss_destroy(self->mycss, 1);
		self->mycss = NULL;
	}
	
	if (self->finder) {
		modest_finder_destroy(self->finder, 1);
		self->finder = NULL;
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

static SV *create_tree_object(myhtml_tree_t *tree, SV *parent, html5_dom_parser_t *parser) {
	tree->context = safemalloc(sizeof(html5_dom_tree_t));
	
	html5_dom_tree_t *tree_obj = (html5_dom_tree_t *) tree->context;
	tree_obj->tree = tree;
	tree_obj->parent = parent;
	tree_obj->parser = parser;
	
	SvREFCNT_inc(parent);
	
	SV *sv = pack_pointer("HTML5::DOM::Tree", tree_obj);
	tree_obj->sv = SvRV(sv);
	
	DOM_GC_TRACE("DOM::Tree::NEW (refcnt=%d)", SvREFCNT(sv));
	
	return sv;
}

static inline const char *get_node_class(myhtml_tag_id_t tag_id) {
	if (tag_id != MyHTML_TAG__UNDEF) {
		if (tag_id == MyHTML_TAG__TEXT) {
			return "HTML5::DOM::Text";
		} else if (tag_id == MyHTML_TAG__COMMENT) {
			return "HTML5::DOM::Comment";
		} else if (tag_id == MyHTML_TAG__DOCTYPE) {
			return "HTML5::DOM::DocType";
		}
		return "HTML5::DOM::Element";
	}
	return "HTML5::DOM::Node";
}

static SV *node_to_sv(myhtml_tree_node_t *node) {
	if (!node)
		return &PL_sv_undef;
	
	SV *sv = (SV *) myhtml_node_get_data(node);
	if (!sv) {
		SV *sv_ref = pack_pointer(get_node_class(node->tag_id), (void *) node);
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

static mystatus_t html5_dom_init_css(html5_dom_parser_t *parser) {
	mystatus_t status = MyCSS_STATUS_OK;
	
	if (!parser->mycss) {
		parser->mycss = mycss_create();
		status = mycss_init(parser->mycss);
		if (status) {
			mycss_destroy(parser->mycss, 1);
			parser->mycss = NULL;
			return status;
		}
	}
	
	if (!parser->mycss_entry) {
		parser->mycss_entry = mycss_entry_create();
		status = mycss_entry_init(parser->mycss, parser->mycss_entry);
		if (status) {
			mycss_entry_destroy(parser->mycss_entry, 1);
			mycss_destroy(parser->mycss, 1);
			parser->mycss = NULL;
			parser->mycss_entry = NULL;
			return status;
		}
	}
	
	return status;
}

static mycss_selectors_list_t *html5_parse_selector(mycss_entry_t *entry, const char *query, size_t query_len, mystatus_t *status_out) {
	mystatus_t status;
	
	*status_out = MyCSS_STATUS_OK;
	
    mycss_selectors_list_t *list = mycss_selectors_parse(mycss_entry_selectors(entry), MyENCODING_UTF_8, query, query_len, &status);
    if (status || list == NULL || (list->flags & MyCSS_SELECTORS_FLAGS_SELECTOR_BAD)) {
		if (list)
			mycss_selectors_list_destroy(mycss_entry_selectors(entry), list, true);
		*status_out = status;
		return NULL;
	}
	
	return list;
}

static void _modest_finder_callback_found_width_one_node(modest_finder_t *finder, myhtml_tree_node_t *node, 
	mycss_selectors_list_t *selector_list, mycss_selectors_entry_t *selector, mycss_selectors_specificity_t *spec, void *ctx)
{
	myhtml_tree_node_t **result_node = (myhtml_tree_node_t **) ctx;
	if (!*result_node)
		*result_node = node;
}

static void *html5_node_finder(html5_dom_parser_t *parser, modest_finder_selector_combinator_f func, 
		myhtml_tree_node_t *scope, mycss_selectors_entries_list_t *list, size_t list_size, mystatus_t *status_out, bool one)
{
	*status_out = MODEST_STATUS_OK;
	
	if (!scope)
		return NULL;
	
	// Init finder
	mystatus_t status;
	if (parser->finder) {
		parser->finder = modest_finder_create();
		status = modest_finder_init(parser->finder);
		if (status) {
			*status_out = status;
			modest_finder_destroy(parser->finder, 1);
			return NULL;
		}
	}
	
	if (one) {
		// Process selector entries
		myhtml_tree_node_t *node = NULL;
		for (size_t i = 0; i < list_size; ++i) {
			func(parser->finder, scope, NULL, list[i].entry, &list[i].specificity, 
				_modest_finder_callback_found_width_one_node, &node);
			
			if (node)
				break;
		}
		
		return (void *) node;
	} else {
		// Init collection for results
		myhtml_collection_t *collection = myhtml_collection_create(4096, &status);
		if (status) {
			*status_out = MODEST_STATUS_ERROR_MEMORY_ALLOCATION;
			return NULL;
		}
		
		// Process selector entries
		for (size_t i = 0; i < list_size; ++i) {
			func(parser->finder, scope, NULL, list[i].entry, &list[i].specificity, 
				modest_finder_callback_found_with_collection, collection);
		}
		
		return (void *) collection;
	}
}

static modest_finder_selector_combinator_f html5_find_selector_func(const char *c, int combo_len) {
	if (combo_len == 2) {
		if (c[0] == '|' && c[1] == '|')
			return modest_finder_node_combinator_column;
		if ((c[0] == '>' && c[1] == '>'))
			return modest_finder_node_combinator_descendant;
	} else if (combo_len == 1) {
		if (c[0] == '>')
			return modest_finder_node_combinator_child;
		if (c[0] == '+')
			return modest_finder_node_combinator_next_sibling;
		if (c[0] == '~')
			return modest_finder_node_combinator_following_sibling;
	}
	return modest_finder_node_combinator_begin;
}

static SV *html5_node_find(CV *cv, html5_dom_parser_t *parser, myhtml_tree_node_t *scope, SV *query, SV *combinator, bool one) {
	mystatus_t status;
	mycss_selectors_entries_list_t *list = NULL;
	size_t list_size = 0;
	mycss_selectors_list_t *selector = NULL;
	modest_finder_selector_combinator_f selector_func = modest_finder_node_combinator_begin;
	SV *result = &PL_sv_undef;
	
	// Custom combinator as args
	if (combinator) {
		query = sv_stringify(query);
		
		STRLEN combo_len;
		const char *combo = SvPV_const(combinator, combo_len);
		
		if (combo_len > 0)
			selector_func = html5_find_selector_func(combo, combo_len);
	}
	
	if (SvROK(query)) {
		if (sv_derived_from(query, "HTML5::DOM::CSS::Selector")) { // Precompiler selectors
			html5_css_selector_t *selector = INT2PTR(html5_css_selector_t *, SvIV((SV*)SvRV(query)));
			list = selector->list->entries_list;
			list_size = selector->list->entries_list_length;
		} else if (sv_derived_from(query, "HTML5::DOM::CSS::Selector::Entry")) { // One precompiled selector
			html5_css_selector_entry_t *selector = INT2PTR(html5_css_selector_entry_t *, SvIV((SV*)SvRV(query)));
			list = selector->list;
			list_size = 1;
		} else {
			sub_croak(cv, "%s: %s is not of type %s or %s", "HTML5::DOM::Tree::find", "query", "HTML5::DOM::CSS::Selector", "HTML5::DOM::CSS::Selector::Entry");
		}
	} else {
		// String selector, compile it
		query = sv_stringify(query);
		
		STRLEN query_len;
		const char *query_str = SvPV_const(query, query_len);
		
		status = html5_dom_init_css(parser);
		if (status)
			sub_croak(cv, "mycss_init failed: %d (%s)", status, modest_strerror(status));
		
		selector = html5_parse_selector(parser->mycss_entry, query_str, query_len, &status);
		
		if (!selector)
			sub_croak(cv, "bad selector: %s", query_str);
		
		list = selector->entries_list;
		list_size = selector->entries_list_length;
	}
	
	if (one) { // search one element
		myhtml_tree_node_t *node = (myhtml_tree_node_t *) html5_node_finder(parser, selector_func, scope, list, list_size, &status, 1);
		result = node_to_sv(node);
	} else { // search multiple elements
		myhtml_collection_t *collection = (myhtml_collection_t *) html5_node_finder(parser, selector_func, scope, list, list_size, &status, 0);
		result = collection_to_blessed_array(collection);
		if (collection)
			myhtml_collection_destroy(collection);
	}
	
	// destroy parsed selector
	if (selector)
		mycss_selectors_list_destroy(mycss_entry_selectors(parser->mycss_entry), selector, true);
	
	return result;
}

MODULE = HTML5::DOM  PACKAGE = HTML5::DOM

#################################################################
# HTML5::DOM (Parser)
#################################################################
HTML5::DOM
new(...)
CODE:
	DOM_GC_TRACE("DOM::new");
	
	mystatus_t status;
	
	html5_dom_parser_t *self = (html5_dom_parser_t *) safemalloc(sizeof(html5_dom_parser_t));
	memset(self, 0, sizeof(html5_dom_parser_t));
	
	self->myhtml = myhtml_create();
	status = myhtml_init(self->myhtml, MyHTML_OPTIONS_DEFAULT, 1, 0);
	if (status) {
		html5_dom_parser_free(self);
		sub_croak(cv, "myhtml_init failed: %d (%s)", status, modest_strerror(status));
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
			sub_croak(cv, "myhtml_tree_init failed: %d (%s)", status, modest_strerror(status));
		}
		myhtml_encoding_set(self->tree, MyENCODING_UTF_8);
	}
	
	STRLEN html_length;
	const char *html_str = SvPV_const(html, html_length);
	
	status = myhtml_parse_chunk(self->tree, html_str, html_length);
	if (status) {
		myhtml_tree_destroy(self->tree);
		sub_croak(cv, "myhtml_parse_chunk failed: %d (%s)", status, modest_strerror(status));
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
		sub_croak(cv, "call parseChunk first");
	
	status = myhtml_parse_chunk_end(self->tree);
	if (status) {
		myhtml_tree_destroy(self->tree);
		sub_croak(cv, "myhtml_parse_chunk failed:%d (%s)", status, modest_strerror(status));
	}
	
	RETVAL = create_tree_object(self->tree, SvRV(ST(0)), self);
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
		sub_croak(cv, "myhtml_tree_init failed: %d (%s)", status, modest_strerror(status));
	}
	
	STRLEN html_length;
	const char *html_str = SvPV_const(html, html_length);
	
	status = myhtml_parse(tree, MyENCODING_UTF_8, html_str, html_length);
	if (status) {
		myhtml_tree_destroy(tree);
		sub_croak(cv, "myhtml_parse failed: %d (%s)", status, modest_strerror(status));
	}
	
	RETVAL = create_tree_object(tree, SvRV(ST(0)), self);
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM self)
CODE:
	DOM_GC_TRACE("DOM::DESTROY (refs=%d)", SvREFCNT(SvRV(ST(0))));
	html5_dom_parser_free(self);



#################################################################
# HTML5::DOM::Tree
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::Tree

SV *
body(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_body(self->tree));
OUTPUT:
	RETVAL

SV *
createElement(HTML5::DOM::Tree self, SV *tag, SV *ns_name = NULL)
CODE:
	// Get namespace id by name
	myhtml_namespace_t ns = MyHTML_NAMESPACE_HTML;
	if (ns_name) {
		ns_name = sv_stringify(ns_name);
		STRLEN ns_name_len;
		const char *ns_name_str = SvPV_const(ns_name, ns_name_len);
		if (!myhtml_namespace_id_by_name(ns_name_str, ns_name_len, &ns))
			sub_croak(cv, "unknown namespace: %s", ns_name_str);
	}
	
	// Get tag id by name
	tag = sv_stringify(tag);
	STRLEN tag_len;
	const char *tag_str = SvPV_const(tag, tag_len);
	
	myhtml_tag_id_t tag_id;
	const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_name(self->tree->tags, tag_str, tag_len);
	if (tag_ctx) {
		tag_id = tag_ctx->id;
	} else {
		// add custom tag
		tag_id = myhtml_tag_add(self->tree->tags, tag_str, tag_len, MyHTML_TOKENIZER_STATE_DATA, true);
	}
	
	// create new tag
	RETVAL = node_to_sv(myhtml_node_create(self->tree, tag_id, ns));
OUTPUT:
	RETVAL

SV *
createComment(HTML5::DOM::Tree self, SV *text)
CODE:
	text = sv_stringify(text);
	STRLEN text_len;
	const char *text_str = SvPV_const(text, text_len);
	myhtml_tree_node_t *node = myhtml_node_create(self->tree, MyHTML_TAG__COMMENT, MyHTML_NAMESPACE_HTML);
	myhtml_node_text_set(node, text_str, text_len, self->tree->encoding);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

SV *
createTextNode(HTML5::DOM::Tree self, SV *text)
CODE:
	text = sv_stringify(text);
	STRLEN text_len;
	const char *text_str = SvPV_const(text, text_len);
	myhtml_tree_node_t *node = myhtml_node_create(self->tree, MyHTML_TAG__TEXT, MyHTML_NAMESPACE_HTML);
	myhtml_node_text_set(node, text_str, text_len, self->tree->encoding);
	RETVAL = node_to_sv(node);
OUTPUT:
	RETVAL

SV *
head(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_head(self->tree));
OUTPUT:
	RETVAL

SV *
root(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_node_html(self->tree));
OUTPUT:
	RETVAL

SV *
document(HTML5::DOM::Tree self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_get_document(self->tree));
OUTPUT:
	RETVAL

SV *
find(HTML5::DOM::Tree self, SV *query, SV *combinator = NULL)
ALIAS:
	at = 1
CODE:
	myhtml_tree_node_t *scope = myhtml_tree_get_document(self->tree);
	if (!scope)
		scope = myhtml_tree_get_node_html(self->tree);
	RETVAL = html5_node_find(cv, self->parser, scope, query, combinator, ix == 1);
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
	DOM_GC_TRACE("DOM::Tree::DESTROY (refs=%d)", SvREFCNT(SvRV(ST(0))));
	void *context = self->tree->context;
	myhtml_tree_destroy(self->tree);
	SvREFCNT_dec(self->parent);
	safefree(context);



#################################################################
# HTML5::DOM::Node
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::Node
HTML5::DOM::Node
new(...)
CODE:
	sub_croak(cv, "Can't manualy create node");
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
	RETVAL = newSVpv("", 0);
	if (recursive) {
		if (self->tag_id == MyHTML_TAG__UNDEF) { // hack for document node :(
			myhtml_tree_node_t *node = myhtml_node_child(self);
			while (node) {
				myhtml_serialization_tree_callback(node, sv_serialization_callback, RETVAL);
				node = myhtml_node_next(node);
			}
		} else {
			myhtml_serialization_tree_callback(self, sv_serialization_callback, RETVAL);
		}
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
	if (!node_is_element(self)) {
		size_t text_len = 0;
		const char *text = myhtml_node_text(self, &text_len);
		RETVAL = newSVpv(text ? text : "", text_len);
	} else {
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

# Remove node from tree
SV *
remove(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_node_remove(self));
OUTPUT:
	RETVAL

# Append child to parent before current node
SV *
before(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!myhtml_node_parent(self))
		sub_croak(cv, "can't insert after detached node");
	myhtml_tree_node_insert_before(self, child);
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Append child to parent after current node
SV *
after(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!myhtml_node_parent(self))
		sub_croak(cv, "can't insert before detached node");
	myhtml_tree_node_insert_after(self, child);
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Clone node
SV *
append(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!node_is_element(self))
		sub_croak(cv, "can't append children to non-element node");
	myhtml_tree_node_add_child(self, child);
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Clone node
SV *
clone(HTML5::DOM::Node self)
CODE:
	RETVAL = node_to_sv(myhtml_tree_node_clone(self));
OUTPUT:
	RETVAL

bool
selfClosed(HTML5::DOM::Node self)
CODE:
	RETVAL = myhtml_node_is_close_self(self);
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::Node self)
CODE:
	SV *sv = (SV *) myhtml_node_get_data(self);
	
	DOM_GC_TRACE("DOM::Node::DESTROY (refcnt=%d)", sv ? SvREFCNT(sv) : -666);
	
	if (sv) {
		html5_dom_tree_t *tree = (html5_dom_tree_t *) self->tree->context;
		myhtml_node_set_data(self, NULL);
		// detached node, can be deleted
		if (!myhtml_node_parent(self) && self != myhtml_tree_get_document(self->tree))
			myhtml_tree_node_delete_recursive(self);
		SvREFCNT_dec(tree->sv);
	}

#################################################################
# HTML5::DOM::Element (extends Node)
#################################################################
# Find by css query
SV *
find(HTML5::DOM::Node self, SV *query, SV *combinator = NULL)
ALIAS:
	at = 1
CODE:
	html5_dom_tree_t *tree_context = (html5_dom_tree_t *) self->tree->context;
	RETVAL = html5_node_find(cv, tree_context->parser, self, query, combinator, ix == 1);
OUTPUT:
	RETVAL

# Find by tag name
SV *
findTag(HTML5::DOM::Node self, SV *tag)
CODE:
	tag = sv_stringify(tag);
	
	STRLEN tag_len;
	const char *tag_str = SvPV_const(tag, tag_len);
	
	myhtml_collection_t *collection = myhtml_get_nodes_by_name_in_scope(self->tree, NULL, self, tag_str, tag_len, NULL);
	RETVAL = collection_to_blessed_array(collection);
	
	if (collection)
		myhtml_collection_destroy(collection);
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

#################################################################
# HTML5::DOM::CSS (Parser)
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::CSS
HTML5::DOM::CSS
new(...)
CODE:
	DOM_GC_TRACE("DOM::CSS::new");
	mystatus_t status;
	
	mycss_t *mycss = mycss_create();
	status = mycss_init(mycss);
	if (status) {
		mycss_destroy(mycss, 1);
		sub_croak(cv, "mycss_init failed: %d (%s)", status, modest_strerror(status));
	}
	
	mycss_entry_t *entry = mycss_entry_create();
	status = mycss_entry_init(mycss, entry);
	if (status) {
		mycss_destroy(mycss, 1);
		mycss_entry_destroy(entry, 1);
		sub_croak(cv, "mycss_entry_init failed: %d (%s)", status, modest_strerror(status));
	}
    
	html5_css_parser_t *self = (html5_css_parser_t *) safemalloc(sizeof(html5_css_parser_t));
	self->mycss = mycss;
	self->entry = entry;
	self->encoding = MyENCODING_UTF_8;
    RETVAL = self;
OUTPUT:
	RETVAL

# Parse css selector
SV *
parseSelector(HTML5::DOM::CSS self, SV *query)
CODE:
	mystatus_t status;
	
	query = sv_stringify(query);
	
	STRLEN query_len;
	const char *query_str = SvPV_const(query, query_len);
	
    mycss_selectors_list_t *list = mycss_selectors_parse(mycss_entry_selectors(self->entry), MyENCODING_UTF_8, query_str, query_len, &status);
    if (list == NULL || (list->flags & MyCSS_SELECTORS_FLAGS_SELECTOR_BAD)) {
		if (list)
			mycss_selectors_list_destroy(mycss_entry_selectors(self->entry), list, true);
		sub_croak(cv, "bad selector: %s", query_str);
	}
	
	DOM_GC_TRACE("DOM::CSS::Selector::NEW");
	html5_css_selector_t *selector = (html5_css_selector_t *) safemalloc(sizeof(html5_css_selector_t));
	selector->parent = SvRV(ST(0));
	selector->list = list;
	selector->parser = self;
	SvREFCNT_inc(selector->parent);
    RETVAL = pack_pointer("HTML5::DOM::CSS::Selector", selector);
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::CSS self)
CODE:
	DOM_GC_TRACE("DOM::CSS::DESTROY (refs=%d)", SvREFCNT(SvRV(ST(0))));
	mycss_entry_destroy(self->entry, 1);
	mycss_destroy(self->mycss, 1);
	safefree(self);


#################################################################
# HTML5::DOM::CSS::Selector
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::CSS::Selector

# Serialize selector to text
SV *
text(HTML5::DOM::CSS::Selector self)
CODE:
	RETVAL = newSVpv("", 0);
	mycss_selectors_serialization_list(mycss_entry_selectors(self->parser->entry), self->list, sv_serialization_callback, RETVAL);
OUTPUT:
	RETVAL

# Get count of selector entries
int
length(HTML5::DOM::CSS::Selector self)
CODE:
	RETVAL = self->list->entries_list_length;
OUTPUT:
	RETVAL

# Get selector entry by index
SV *
entry(HTML5::DOM::CSS::Selector self, int index)
CODE:
	if (index < 0 || index >= self->list->entries_list_length) {
		RETVAL = &PL_sv_undef;
	} else {
		DOM_GC_TRACE("DOM::CSS::Selector::Entry::NEW");
		html5_css_selector_entry_t *entry = (html5_css_selector_entry_t *) safemalloc(sizeof(html5_css_selector_entry_t));
		entry->parent = SvRV(ST(0));
		entry->list = &self->list->entries_list[index];
		entry->parser = self->parser;
		SvREFCNT_inc(entry->parent);
		RETVAL = pack_pointer("HTML5::DOM::CSS::Selector::Entry", entry);
	}
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::CSS::Selector self)
CODE:
	DOM_GC_TRACE("DOM::CSS::Selector::DESTROY (refs=%d)", SvREFCNT(SvRV(ST(0))));
	mycss_selectors_list_destroy(mycss_entry_selectors(self->parser->entry), self->list, true);
	SvREFCNT_dec(self->parent);
	safefree(self);


#################################################################
# HTML5::DOM::CSS::Selector::Entry
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::CSS::Selector::Entry

# Serialize selector to text
SV *
text(HTML5::DOM::CSS::Selector::Entry self)
CODE:
	RETVAL = newSVpv("", 0);
	mycss_selectors_serialization_chain(mycss_entry_selectors(self->parser->entry), self->list->entry, sv_serialization_callback, RETVAL);
OUTPUT:
	RETVAL

# Return selector specificity in hash {a, b, c}
SV *
specificity(HTML5::DOM::CSS::Selector::Entry self)
CODE:
	HV *hash = newHV();
	hv_store_ent(hash, sv_2mortal(newSVpv("a", 1)), newSViv(self->list->specificity.a), 0);
	hv_store_ent(hash, sv_2mortal(newSVpv("b", 1)), newSViv(self->list->specificity.b), 0);
	hv_store_ent(hash, sv_2mortal(newSVpv("c", 1)), newSViv(self->list->specificity.c), 0);
	RETVAL = newRV_noinc((SV *) hash);
OUTPUT:
	RETVAL

# Return selector specificity in array [b, a, c]
SV *
specificityArray(HTML5::DOM::CSS::Selector::Entry self)
CODE:
	AV *arr = newAV();
	av_push(arr, newSViv(self->list->specificity.b));
	av_push(arr, newSViv(self->list->specificity.a));
	av_push(arr, newSViv(self->list->specificity.c));
	RETVAL = newRV_noinc((SV *) arr);
OUTPUT:
	RETVAL

void
DESTROY(HTML5::DOM::CSS::Selector::Entry self)
CODE:
	DOM_GC_TRACE("DOM::CSS::Selector::Entry::DESTROY (refs=%d)", SvREFCNT(SvRV(ST(0))));
	SvREFCNT_dec(self->parent);
	safefree(self);
