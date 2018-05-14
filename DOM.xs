#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"

#include <modest/finder/finder.h>
#include <myhtml/myhtml.h>
#include <myhtml/serialization.h>
#include <mycss/mycss.h>
#include <mycss/selectors/init.h>
#include <mycss/selectors/serialization.h>

// HACK: sv_derived_from_pvn faster than sv_derived_from
#if PERL_BCDVERSION > 0x5015004
	#undef sv_derived_from
	#define sv_derived_from(sv, name) sv_derived_from_pvn(sv, name, sizeof(name) - 1, 0)
#else
	#define sv_derived_from_pvn(sv, name, len) sv_derived_from(sv, name)
#endif

#define node_is_element(node) (node->tag_id != MyHTML_TAG__UNDEF && node->tag_id != MyHTML_TAG__TEXT && node->tag_id != MyHTML_TAG__COMMENT && node->tag_id != MyHTML_TAG__DOCTYPE)

//#define DOM_GC_TRACE(msg, ...) fprintf(stderr, "[GC] " msg "\n", ##__VA_ARGS__);
#define DOM_GC_TRACE(...)

#define sub_croak(cv, msg, ...) do { \
	const GV *const __gv = CvGV(cv); \
	if (__gv) { \
		const char *__gvname = GvNAME(__gv); \
		const HV *__stash = GvSTASH(__gv); \
		const char *__hvname = __stash ? HvNAME(__stash) : NULL; \
		croak("%s%s%s(): " msg, __hvname ? __hvname : __gvname, __hvname ? "::" : "", __hvname ? __gvname : "", ##__VA_ARGS__); \
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
	myhtml_tag_id_t fragment_tag_id;
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

static inline bool html5_dom_is_fragment(myhtml_tree_node_t *node) {
	html5_dom_tree_t *context = (html5_dom_tree_t *) node->tree->context;
	return context->fragment_tag_id && node->tag_id == context->fragment_tag_id;
}

static const char *modest_strerror(mystatus_t status) {
	switch (status) {
		#include "modest_errors.c"	
	}
	return status ? "UNKNOWN" : "";
}

static void html5_dom_wait_for_tree_done(myhtml_tree_t *tree) {
	#ifndef MyCORE_BUILD_WITHOUT_THREADS
		myhtml_t *myhtml = myhtml_tree_get_myhtml(tree);
		if (myhtml->thread_stream) {
			mythread_queue_list_t* queue_list = myhtml->thread_stream->context;
			if (queue_list)
				mythread_queue_list_wait_for_done(myhtml->thread_stream, queue_list);
		}
	#endif
}

static void html5_dom_wait_for_done(myhtml_tree_node_t *node, bool deep) {
	#ifndef MyCORE_BUILD_WITHOUT_THREADS
		if (node->token)
			myhtml_token_node_wait_for_done(node->tree->token, node->token);
		if (deep) {
			myhtml_tree_node_t *child = myhtml_node_child(node);
			while (child) {
				html5_dom_wait_for_done(child, deep);
				child = myhtml_node_next(child);
			}
		}
	#endif
}

static bool html5_dom_is_done(myhtml_tree_node_t *node, bool deep) {
	#ifndef MyCORE_BUILD_WITHOUT_THREADS
		if (node->token) {
			if ((node->token->type & MyHTML_TOKEN_TYPE_DONE) == 0)
				return false;
		}
		if (deep) {
			myhtml_tree_node_t *child = myhtml_node_child(node);
			while (child) {
				if (!html5_dom_is_done(child, deep))
					return false;
				child = myhtml_node_next(child);
			}
		}
	#endif
	return true;
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
	return MyCORE_STATUS_OK;
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

static inline const char *get_node_class(myhtml_tree_node_t *node) {
	html5_dom_tree_t *context = (html5_dom_tree_t *) node->tree->context;
	if (node->tag_id != MyHTML_TAG__UNDEF) {
		if (node->tag_id == MyHTML_TAG__TEXT) {
			return "HTML5::DOM::Text";
		} else if (node->tag_id == MyHTML_TAG__COMMENT) {
			return "HTML5::DOM::Comment";
		} else if (node->tag_id == MyHTML_TAG__DOCTYPE) {
			return "HTML5::DOM::DocType";
		} else if (context->fragment_tag_id && node->tag_id == context->fragment_tag_id) {
			return "HTML5::DOM::Fragment";
		}
		return "HTML5::DOM::Element";
	}
	
	// Modest myhtml bug - document node has tag_id == MyHTML_TAG__UNDEF
	if (!node->parent && node == myhtml_tree_get_document(node->tree))
		return "HTML5::DOM::Document";
	
	return "HTML5::DOM::Node";
}

static myhtml_tag_id_t html5_dom_tag_id_by_name(myhtml_tree_t *tree, const char *tag_str, size_t tag_len, bool allow_create) {
	const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_name(tree->tags, tag_str, tag_len);
	if (tag_ctx) {
		return tag_ctx->id;
	} else if (allow_create) {
		// add custom tag
		return myhtml_tag_add(tree->tags, tag_str, tag_len, MyHTML_TOKENIZER_STATE_DATA, true);
	}
	return MyHTML_TAG__UNDEF;
}

// Safe copy node from native or foreign tree
static myhtml_tree_node_t *html5_dom_copy_foreign_node(myhtml_tree_t *tree, myhtml_tree_node_t *node) {
	// Create new node
	myhtml_tree_node_t *new_node = myhtml_tree_node_create(tree);
	new_node->tag_id		= node->tag_id;
	new_node->ns			= node->ns;
	
	// Copy custom tag
	if (tree != node->tree && node->tag_id >= MyHTML_TAG_LAST_ENTRY) {
		new_node->tag_id = MyHTML_TAG__UNDEF;
		
		// Get tag name in foreign tree
		const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_id(node->tree->tags, node->tag_id);
		if (tag_ctx) {
			// Get same tag in native tree
			new_node->tag_id = html5_dom_tag_id_by_name(tree, tag_ctx->name, tag_ctx->name_length, true);
		}
	}
	
	if (node->token) {
		// Wait, if node not yet done
		myhtml_token_node_wait_for_done(node->tree->token, node->token);
		
		// Copy node token
		new_node->token = myhtml_token_node_create(tree->token, tree->mcasync_rules_token_id);
		if (!new_node->token) {
			myhtml_tree_node_delete(new_node);
			return NULL;
		}
		
		new_node->token->tag_id			= node->token->tag_id;
		new_node->token->type			= node->token->type;
		new_node->token->attr_first		= NULL;
		new_node->token->attr_last		= NULL;
		new_node->token->raw_begin		= tree != node->tree ? 0 : node->token->raw_begin;
		new_node->token->raw_length		= tree != node->tree ? 0 : node->token->raw_length;
		new_node->token->element_begin	= tree != node->tree ? 0 : node->token->element_begin;
		new_node->token->element_length	= tree != node->tree ? 0 : node->token->element_length;
		new_node->token->type			= new_node->token->type | MyHTML_TOKEN_TYPE_DONE;
		
		// Copy text data (TODO: encoding)
		if (node->token->str.length) {
			mycore_string_init(tree->mchar, tree->mchar_node_id, &new_node->token->str, node->token->str.length + 1);
			mycore_string_append(&new_node->token->str, node->token->str.data, node->token->str.length);
		} else {
			mycore_string_clean_all(&new_node->token->str);
		}
		
		// Copy node attributes
		myhtml_token_attr_t *attr = node->token->attr_first;
		while (attr) {
			myhtml_token_attr_copy(tree->token, attr, new_node->token, tree->mcasync_rules_attr_id);
			attr = attr->next;
		}
	}
    
    return new_node;
}

static SV *node_to_sv(myhtml_tree_node_t *node) {
	if (!node)
		return &PL_sv_undef;
	
	SV *sv = (SV *) myhtml_node_get_data(node);
	if (!sv) {
		SV *node_ref = pack_pointer(get_node_class(node), (void *) node);
		sv = SvRV(node_ref);
		myhtml_node_set_data(node, (void *) sv);
		
		DOM_GC_TRACE("DOM::Node::NEW (new refcnt=%d)", SvREFCNT(sv));
		
		html5_dom_tree_t *tree = (html5_dom_tree_t *) node->tree->context;
		SvREFCNT_inc(tree->sv);
		
		return node_ref;
	} else {
		SV *node_ref = newRV(sv);
		DOM_GC_TRACE("DOM::Node::NEW (reuse refcnt=%d)", SvREFCNT(sv));
		return node_ref;
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

static void _modest_finder_callback_found_with_one_node(modest_finder_t *finder, myhtml_tree_node_t *node, 
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
				_modest_finder_callback_found_with_one_node, &node);
			
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

static SV *html5_node_simple_find(CV *cv, myhtml_tree_node_t *self, SV *key, SV *val, SV *cmp, bool icase, int ix) {
	SV *result = &PL_sv_undef;
	key = sv_stringify(key);
	
	STRLEN key_len;
	const char *key_str = SvPV_const(key, key_len);
	
	myhtml_collection_t *collection = NULL;
	switch (ix) {
		case 0: case 1: // tag name
			collection = myhtml_get_nodes_by_name_in_scope(self->tree, NULL, self, key_str, key_len, NULL);
			result = collection_to_blessed_array(collection);
		break;
		case 2: case 3: // class
			collection = myhtml_get_nodes_by_attribute_value_whitespace_separated(self->tree, NULL, self, false, "class", 5, key_str, key_len, NULL);
			result = collection_to_blessed_array(collection);
		break;
		case 4: case 5: // id (first)
			collection = myhtml_get_nodes_by_attribute_value(self->tree, NULL, self, false, "id", 2, key_str, key_len, NULL);
			if (collection && collection->length)
				result = node_to_sv(collection->list[0]);
		break;
		case 6: case 7: // attribute
			if (val) {
				STRLEN val_len;
				const char *val_str = SvPV_const(val, val_len);
				
				char cmp_type = '=';
				if (cmp) {
					cmp = sv_stringify(cmp);
					STRLEN cmp_len;
					const char *cmp_str = SvPV_const(cmp, cmp_len);
					
					if (cmp_len)
						cmp_type = cmp_str[0];
				}
				
				if (cmp_type == '=') {
					// [key=val]
					collection = myhtml_get_nodes_by_attribute_value(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else if (cmp_type == '~') {
					// [key~=val]
					collection = myhtml_get_nodes_by_attribute_value_whitespace_separated(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else if (cmp_type == '^') {
					// [key^=val]
					collection = myhtml_get_nodes_by_attribute_value_begin(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else if (cmp_type == '$') {
					// [key$=val]
					collection = myhtml_get_nodes_by_attribute_value_end(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else if (cmp_type == '*') {
					// [key*=val]
					collection = myhtml_get_nodes_by_attribute_value_contain(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else if (cmp_type == '|') {
					// [key|=val]
					collection = myhtml_get_nodes_by_attribute_value_hyphen_separated(self->tree, NULL, self, icase, key_str, key_len, val_str, val_len, NULL);
				} else {
					sub_croak(cv, "unknown cmp type: %c", cmp_type);
				}
			} else {
				// [key]
				collection = myhtml_get_nodes_by_attribute_key(self->tree, NULL, self, key_str, key_len, NULL);
			}
			result = collection_to_blessed_array(collection);
		break;
	}
	
	if (collection)
		myhtml_collection_destroy(collection);
	
	return result;
}

static myhtml_tree_node_t *html5_dom_recursive_clone_node(myhtml_tree_t *tree, myhtml_tree_node_t *node) {
	myhtml_tree_node_t *new_node = html5_dom_copy_foreign_node(tree, node);
	myhtml_tree_node_t *child = myhtml_node_child(node);
	while (child) {
		myhtml_tree_node_add_child(new_node, html5_dom_recursive_clone_node(tree, child));
		child = myhtml_node_next(child);
	}
	return new_node;
}

// Safe delete nodes only if it has not perl object representation
static void html5_tree_node_delete_recursive(myhtml_tree_node_t *node) {
	if (!myhtml_node_get_data(node)) {
		myhtml_tree_node_t *child = myhtml_node_child(node);
		if (child) {
			while (child) {
				myhtml_tree_node_t *next = myhtml_node_next(child);
				myhtml_tree_node_remove(child);
				html5_tree_node_delete_recursive(child);
				child = next;
			}
		}
		myhtml_tree_node_delete(node);
	}
}

static myhtml_tree_node_t *html5_dom_parse_fragment(myhtml_tree_t *tree, myhtml_tag_id_t tag_id, myhtml_namespace_t ns, 
	const char *text, size_t length, mystatus_t *status_out)
{
	mystatus_t status;
	
	myhtml_t *parser = myhtml_tree_get_myhtml(tree);
	
	// cteate temorary tree
	myhtml_tree_t *fragment_tree = myhtml_tree_create();
	status = myhtml_tree_init(fragment_tree, parser);
	if (status) {
		*status_out = status;
		myhtml_tree_destroy(tree);
		return NULL;
	}
	
	// parse fragment from text
	status = myhtml_parse_fragment(fragment_tree, tree->encoding, text, length, tag_id, ns);
	if (status) {
		*status_out = status;
		myhtml_tree_destroy(tree);
		return NULL;
	}
	
	// clone fragment from temporary tree to persistent tree
	myhtml_tree_node_t *node = html5_dom_recursive_clone_node(tree, myhtml_tree_get_node_html(fragment_tree));
	
	if (node) {
		html5_dom_tree_t *context = (html5_dom_tree_t *) node->tree->context;
		if (!context->fragment_tag_id)
			context->fragment_tag_id = html5_dom_tag_id_by_name(tree, "-fragment", 9, true);
		node->tag_id = context->fragment_tag_id;
		myhtml_tree_destroy(fragment_tree);
	}
	
	*status_out = status;
	
	return node;
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
	
	html5_dom_wait_for_tree_done(self->tree);
	
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
	
	html5_dom_wait_for_tree_done(tree);
	
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
	myhtml_tag_id_t tag_id = html5_dom_tag_id_by_name(self->tree, tag_str, tag_len, true);
	
	// create new node
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

# Parse fragment
SV *parseFragment(HTML5::DOM::Tree self, SV *text, SV *tag = NULL, SV *ns = NULL)
CODE:
	text = sv_stringify(text);
	STRLEN text_len;
	const char *text_str = SvPV_const(text, text_len);
	
	mystatus_t status;
	myhtml_namespace_t ns_id = MyHTML_NAMESPACE_HTML;
	myhtml_tag_id_t tag_id = MyHTML_TAG_DIV;
	
	if (ns) {
		ns = sv_stringify(ns);
		STRLEN ns_len;
		const char *ns_str = SvPV_const(ns, ns_len);
		
		if (myhtml_namespace_id_by_name(ns_str, ns_len, &ns_id))
			sub_croak(cv, "unknown namespace: %s", ns_str);
	}
	
	if (tag) {
		tag = sv_stringify(tag);
		STRLEN tag_len;
		const char *tag_str = SvPV_const(tag, tag_len);
		tag_id = html5_dom_tag_id_by_name(self->tree, tag_str, tag_len, true);
	}
	
	myhtml_tree_node_t *node = html5_dom_parse_fragment(self->tree, tag_id, ns_id, text_str, text_len, &status);
	if (status)
		sub_croak(cv, "myhtml_parse_fragment failed: %d (%s)", status, modest_strerror(status));
	
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
	at					= 1
	querySelector		= 2
	querySelectorAll	= 3
CODE:
	myhtml_tree_node_t *scope = myhtml_tree_get_document(self->tree);
	if (!scope)
		scope = myhtml_tree_get_node_html(self->tree);
	RETVAL = html5_node_find(cv, self->parser, scope, query, combinator, ix == 1 || ix == 2);
OUTPUT:
	RETVAL

# Wait for parsing done (when async mode)
SV *
wait(HTML5::DOM::Tree self)
CODE:
	html5_dom_wait_for_tree_done(self->tree);
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# True if parsing done (when async mode)
bool
parsed(HTML5::DOM::Tree self)
CODE:
	RETVAL = true;
	
	#ifndef MyCORE_BUILD_WITHOUT_THREADS
		myhtml_t *myhtml = myhtml_tree_get_myhtml(self->tree);
		if (myhtml->thread_stream) {
			mythread_queue_list_t* queue_list = myhtml->thread_stream->context;
			RETVAL = mythread_queue_list_see_for_done(myhtml->thread_stream, queue_list);
		}
	#endif
OUTPUT:
	RETVAL

# findTag(val), getElementsByTagName(val)									- get nodes by tag name
# findClass(val), getElementsByClassName(val)								- get nodes by class name
# findId(val), getElementById(val)											- get node by id
# findAttr(key), getElementByAttribute(key)									- get nodes by attribute key
# findAttr(key, val, case, cmp), getElementByAttribute(key, val, case, cmp)	- get nodes by attribute value
SV *
findTag(HTML5::DOM::Tree self, SV *key, SV *val = NULL, bool icase = false, SV *cmp = NULL)
ALIAS:
	getElementsByTagName	= 1
	findClass				= 2
	getElementsByClassName	= 3
	findId					= 4
	getElementById			= 5
	findAttr				= 6
	getElementByAttribute	= 7
CODE:
	RETVAL = html5_node_simple_find(cv, myhtml_tree_get_document(self->tree), key, val, cmp, icase, ix);
OUTPUT:
	RETVAL

# Tag id by tag name
SV *
tag2id(HTML5::DOM::Tree self, SV *tag)
CODE:
	tag = sv_stringify(tag);
	STRLEN tag_len;
	const char *tag_str = SvPV_const(tag, tag_len);
	RETVAL = newSViv(html5_dom_tag_id_by_name(self->tree, tag_str, tag_len, true));
OUTPUT:
	RETVAL

# Tag name by tag id
SV *
id2tag(HTML5::DOM::Tree self, int tag_id)
CODE:
	RETVAL = &PL_sv_undef;
	const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_id(self->tree->tags, tag_id);
	if (tag_ctx)
		RETVAL = newSVpv(tag_ctx->name ? tag_ctx->name : "", tag_ctx->name_length);
OUTPUT:
	RETVAL

# Namespace id by namepsace name
SV *
namespace2id(HTML5::DOM::Tree self, SV *ns)
CODE:
	ns = sv_stringify(ns);
	STRLEN ns_len;
	const char *ns_str = SvPV_const(ns, ns_len);
	
	myhtml_namespace_t ns_id;
	if (!myhtml_namespace_id_by_name(ns_str, ns_len, &ns_id))
		ns_id = MyHTML_NAMESPACE_UNDEF;
	
	RETVAL = newSViv(ns_id);
OUTPUT:
	RETVAL

# Namespace name by namepsace id
SV *
id2namespace(HTML5::DOM::Tree self, int ns_id)
CODE:
	size_t ns_len = 0;
	const char *ns_name = myhtml_namespace_name_by_id(ns_id, &ns_len);
	RETVAL = ns_name ? newSVpv(ns_name, ns_len) : &PL_sv_undef;
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
# Tag id
SV *
tagId(HTML5::DOM::Node self, int new_tag_id = -1)
CODE:
	if (new_tag_id >= 0) {
		const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_id(self->tree->tags, new_tag_id);
		if (tag_ctx) {
			self->tag_id = new_tag_id;
		} else {
			sub_croak(cv, "unknown tag id %d", new_tag_id);
		}
		
		RETVAL = SvREFCNT_inc(ST(0));
	} else {
		RETVAL = newSViv(self->tag_id);
	}
OUTPUT:
	RETVAL

# Namespace id
SV *
namespaceId(HTML5::DOM::Node self, int new_ns_id = -1)
CODE:
	if (new_ns_id >= 0) {
		if (!myhtml_namespace_name_by_id(new_ns_id, NULL)) {
			sub_croak(cv, "unknown namespace id %d", new_ns_id);
		} else {
			myhtml_node_namespace_set(self, new_ns_id);
		}
		RETVAL = SvREFCNT_inc(ST(0));
	} else {
		RETVAL = newSViv(myhtml_node_namespace(self));
	}
OUTPUT:
	RETVAL

# Tag name
SV *
tag(HTML5::DOM::Node self, SV *new_tag_name = NULL)
CODE:
	myhtml_tree_t *tree = self->tree;
	
	// Set new tag name
	if (new_tag_name) {
		new_tag_name = sv_stringify(new_tag_name);
		STRLEN new_tag_name_len;
		const char *new_tag_name_str = SvPV_const(new_tag_name, new_tag_name_len);
		
		myhtml_tag_id_t tag_id = html5_dom_tag_id_by_name(self->tree, new_tag_name_str, new_tag_name_len, true);
		self->tag_id = tag_id;
		
		RETVAL = SvREFCNT_inc(ST(0));
	}
	// Get tag name
	else {
		RETVAL = &PL_sv_undef;
		
		if (tree && tree->tags) {
			const myhtml_tag_context_t *tag_ctx = myhtml_tag_get_by_id(tree->tags, self->tag_id);
			if (tag_ctx)
				RETVAL = newSVpv(tag_ctx->name, tag_ctx->name_length);
		}
	}
OUTPUT:
	RETVAL

# Namespace name
SV *
namespace(HTML5::DOM::Node self, SV *new_ns = NULL)
CODE:
	myhtml_tree_t *tree = self->tree;
	
	// Set new tag namespace
	if (new_ns) {
		new_ns = sv_stringify(new_ns);
		STRLEN new_ns_len;
		const char *new_ns_str = SvPV_const(new_ns, new_ns_len);
		
		myhtml_namespace_t ns;
		if (!myhtml_namespace_id_by_name(new_ns_str, new_ns_len, &ns))
			sub_croak(cv, "unknown namespace: %s", new_ns_str);
		myhtml_node_namespace_set(self, ns);
		
		RETVAL = SvREFCNT_inc(ST(0));
	}
	// Get namespace name
	else {
		size_t ns_name_len;
		const char *ns_name = myhtml_namespace_name_by_id(myhtml_node_namespace(self), &ns_name_len);
		RETVAL = newSVpv(ns_name ? ns_name : "", ns_name_len);
	}
OUTPUT:
	RETVAL

# Non-recursive html serialization (example: <div id="some_id">)
SV *
nodeHtml(HTML5::DOM::Node self, SV *text = NULL)
CODE:
	RETVAL = newSVpv("", 0);
	myhtml_serialization_node_callback(self, sv_serialization_callback, RETVAL);
OUTPUT:
	RETVAL

# Node::text()			- Serialize tree to text
# Node::html(text)		- Ignore
# Element::html(text)	- Remove all children nodes and add parsed fragment, return self
SV *
html(HTML5::DOM::Node self, SV *text = NULL)
ALIAS:
	innerHTML	= 1
	outerHTML	= 2
CODE:
	if (text) {
		if (ix == 2)
			sub_croak(cv, "outerHTML is read only");
		
		text = sv_stringify(text);
		STRLEN text_len;
		const char *text_str = SvPV_const(text, text_len);
		
		if (node_is_element(self)) { // parse fragment and replace all node childrens with it
			// parse fragment
			mystatus_t status;
			myhtml_tree_node_t *fragment = html5_dom_parse_fragment(self->tree, self->tag_id, myhtml_node_namespace(self), text_str, text_len, &status);
			if (status)
				sub_croak(cv, "myhtml_parse_fragment failed: %d (%s)", status, modest_strerror(status));
			
			// remove all child nodes
			myhtml_tree_node_t *node = myhtml_node_child(self);
			while (node) {
				myhtml_tree_node_t *next = myhtml_node_next(node);
				myhtml_tree_node_remove(node);
				html5_tree_node_delete_recursive(node);
				node = next;
			}
			
			myhtml_tree_node_add_child(self, fragment);
			
			// add fragment
			node = myhtml_node_child(fragment);
			while (node) {
				myhtml_tree_node_t *next = myhtml_node_next(node);
				myhtml_tree_node_remove(node);
				myhtml_tree_node_add_child(self, node);
				node = next;
			}
			
			// free fragment
			html5_tree_node_delete_recursive(fragment);
		} else { // same as nodeValue, why not?
			myhtml_node_text_set(self, text_str, text_len, self->tree->encoding);
		}
		RETVAL = SvREFCNT_inc(ST(0));
	} else {
		RETVAL = newSVpv("", 0);
		if (self->tag_id == MyHTML_TAG__UNDEF || ix == 1 || html5_dom_is_fragment(self)) { // innerHTML
			myhtml_tree_node_t *node = myhtml_node_child(self);
			while (node) {
				myhtml_serialization_tree_callback(node, sv_serialization_callback, RETVAL);
				node = myhtml_node_next(node);
			}
		} else { // outerHTML
			myhtml_serialization_tree_callback(self, sv_serialization_callback, RETVAL);
		}
	}
OUTPUT:
	RETVAL

# Node::text()			- Serialize tree to text
# Node::text(text)		- Set node value, return self
# Element::text(text)	- Remove all children nodes and add text node, return self
SV *
text(HTML5::DOM::Node self, SV *text = NULL)
ALIAS:
	nodeValue	= 1
	innerText	= 2
	textContent	= 3
CODE:
	myhtml_tree_t *tree = self->tree;
	if (!node_is_element(self)) {
		if (text) { // set node value
			text = sv_stringify(text);
			STRLEN text_len;
			const char *text_str = SvPV_const(text, text_len);
			
			myhtml_node_text_set(self, text_str, text_len, self->tree->encoding);
			RETVAL = SvREFCNT_inc(ST(0));
		} else { // get node value
			size_t text_len = 0;
			const char *text = myhtml_node_text(self, &text_len);
			RETVAL = newSVpv(text ? text : "", text_len);
		}
	} else if (ix == 1) { // nodeValue can't used for elements
		RETVAL = &PL_sv_undef;
	} else {
		if (text) { // remove all childrens and add text node
			text = sv_stringify(text);
			STRLEN text_len;
			const char *text_str = SvPV_const(text, text_len);
			
			myhtml_tree_node_t *node = myhtml_node_child(self);
			while (node) {
				myhtml_tree_node_t *next = myhtml_node_next(node);
				myhtml_tree_node_remove(node);
				html5_tree_node_delete_recursive(node);
				node = next;
			}
			
			myhtml_tree_node_t *text_node = myhtml_node_create(self->tree, MyHTML_TAG__TEXT, myhtml_node_namespace(self));
			myhtml_node_text_set(text_node, text_str, text_len, self->tree->encoding);
			myhtml_tree_node_add_child(self, text_node);
			RETVAL = SvREFCNT_inc(ST(0));
		} else { // recursive serialize node to text
			RETVAL = newSVpv("", 0);
			html5_dom_recursive_node_text(self, RETVAL);
		}
	}
OUTPUT:
	RETVAL

# Wait for node parsing done (when async mode)
SV *
wait(HTML5::DOM::Node self, bool deep = false)
CODE:
	html5_dom_wait_for_done(self, deep);
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# True if node parsing done (when async mode)
bool
parsed(HTML5::DOM::Node self, bool deep = false)
CODE:
	RETVAL = html5_dom_is_done(self, deep);
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
	
	if (self->tree != child->tree) {
		myhtml_tree_node_remove(child);
		child = html5_dom_recursive_clone_node(self->tree, child);
	}
	
	if (html5_dom_is_fragment(child)) {
		myhtml_tree_node_t *fragment_child = myhtml_node_child(child);
		while (fragment_child) {
			myhtml_tree_node_insert_before(self, fragment_child);
			fragment_child = myhtml_node_next(fragment_child);
		}
	} else {
		myhtml_tree_node_insert_before(self, child);
	}
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Append child to parent after current node
SV *
after(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!myhtml_node_parent(self))
		sub_croak(cv, "can't insert before detached node");
	
	if (self->tree != child->tree) {
		myhtml_tree_node_remove(child);
		child = html5_dom_recursive_clone_node(self->tree, child);
	}
	
	if (html5_dom_is_fragment(child)) {
		myhtml_tree_node_t *fragment_child = myhtml_node_last_child(child);
		while (fragment_child) {
			myhtml_tree_node_insert_after(self, fragment_child);
			fragment_child = myhtml_node_prev(fragment_child);
		}
	} else {
		myhtml_tree_node_insert_after(self, child);
	}
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Append node child
SV *
append(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!node_is_element(self))
		sub_croak(cv, "can't append children to non-element node");
	
	if (self->tree != child->tree) {
		myhtml_tree_node_remove(child);
		child = html5_dom_recursive_clone_node(self->tree, child);
	}
	
	if (html5_dom_is_fragment(child)) {
		myhtml_tree_node_t *fragment_child = myhtml_node_child(child);
		while (fragment_child) {
			myhtml_tree_node_add_child(self, fragment_child);
			fragment_child = myhtml_node_next(fragment_child);
		}
	} else {
		myhtml_tree_node_add_child(self, child);
	}
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Prepend node child
SV *
prepend(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (!node_is_element(self))
		sub_croak(cv, "can't prepend children to non-element node");
	
	if (self->tree != child->tree) {
		myhtml_tree_node_remove(child);
		child = html5_dom_recursive_clone_node(self->tree, child);
	}
	
	myhtml_tree_node_t *first_node = myhtml_node_child(self);
	if (html5_dom_is_fragment(child)) {
		myhtml_tree_node_t *fragment_child = myhtml_node_child(child);
		while (fragment_child) {
			myhtml_tree_node_add_child(self, fragment_child);
			if (first_node) {
				myhtml_tree_node_insert_before(first_node, fragment_child);
			} else {
				myhtml_tree_node_add_child(self, fragment_child);
			}
			fragment_child = myhtml_node_next(fragment_child);
		}
	} else {
		if (first_node) {
			myhtml_tree_node_insert_before(first_node, child);
		} else {
			myhtml_tree_node_add_child(self, child);
		}
	}
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Replace node with child
SV *
replace(HTML5::DOM::Node self, HTML5::DOM::Node child)
CODE:
	if (self->tree != child->tree) {
		myhtml_tree_node_remove(child);
		child = html5_dom_recursive_clone_node(self->tree, child);
	}
	
	if (html5_dom_is_fragment(child)) {
		myhtml_tree_node_t *fragment_child = myhtml_node_child(child);
		while (fragment_child) {
			myhtml_tree_node_t *fragment_child = myhtml_node_child(child);
			while (fragment_child) {
				myhtml_tree_node_insert_before(self, fragment_child);
				fragment_child = myhtml_node_next(fragment_child);
			}
		}
	} else {
		myhtml_tree_node_insert_before(self, child);
	}
	
	myhtml_tree_node_remove(self);
	
	RETVAL = SvREFCNT_inc(ST(0));
OUTPUT:
	RETVAL

# Clone node
SV *
clone(HTML5::DOM::Node self, bool deep = false, HTML5::DOM::Tree new_tree = NULL)
CODE:
	myhtml_tree_t *tree = new_tree ? new_tree->tree : self->tree;
	if (deep) {
		RETVAL = node_to_sv(html5_dom_recursive_clone_node(tree, self));
	} else {
		RETVAL = node_to_sv(html5_dom_copy_foreign_node(tree, self));
	}
OUTPUT:
	RETVAL

# True if node is void
bool
isVoid(HTML5::DOM::Node self)
CODE:
	RETVAL = myhtml_node_is_void_element(self);
OUTPUT:
	RETVAL

# True if node is self-closed
bool
isSelfClosed(HTML5::DOM::Node self)
CODE:
	RETVAL = myhtml_node_is_close_self(self);
OUTPUT:
	RETVAL

# Node position in text input
SV *
position(HTML5::DOM::Node self)
CODE:
	HV *hash = newHV();
	hv_store_ent(hash, sv_2mortal(newSVpv("raw_begin", 9)), newSViv(self->token ? self->token->raw_begin : 0), 0);
	hv_store_ent(hash, sv_2mortal(newSVpv("raw_length", 10)), newSViv(self->token ? self->token->raw_length : 0), 0);
	hv_store_ent(hash, sv_2mortal(newSVpv("element_begin", 13)), newSViv(self->token ? self->token->element_begin : 0), 0);
	hv_store_ent(hash, sv_2mortal(newSVpv("element_length", 14)), newSViv(self->token ? self->token->element_length : 0), 0);
	RETVAL = newRV_noinc((SV *) hash);
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
		if (!myhtml_node_parent(self) && self != myhtml_tree_get_document(self->tree)) {
			if (self == self->tree->node_html) {
				self->tree->node_html = NULL;
			} else if (self == self->tree->node_body) {
				self->tree->node_body = NULL;
			} else if (self == self->tree->node_head) {
				self->tree->node_head = NULL;
			} else if (self == self->tree->node_form) {
				self->tree->node_form = NULL;
			} else if (self == self->tree->fragment) {
				self->tree->fragment = NULL;
			} else if (self == self->tree->document) {
				self->tree->document = NULL;
			}
			DOM_GC_TRACE("=> DOM::Node::FREE");
			html5_tree_node_delete_recursive(self);
		}
		SvREFCNT_dec(tree->sv);
	}

#################################################################
# HTML5::DOM::Element (extends Node)
#################################################################
# Find by css query
SV *
find(HTML5::DOM::Node self, SV *query, SV *combinator = NULL)
ALIAS:
	at					= 1
	querySelector		= 2
	querySelectorAll	= 3
CODE:
	html5_dom_tree_t *tree_context = (html5_dom_tree_t *) self->tree->context;
	RETVAL = html5_node_find(cv, tree_context->parser, self, query, combinator, ix == 1 || ix == 2);
OUTPUT:
	RETVAL

# findTag(val), getElementsByTagName(val)									- get nodes by tag name
# findClass(val), getElementsByClassName(val)								- get nodes by class name
# findId(val), getElementById(val)											- get node by id
# findAttr(key), getElementByAttribute(key)									- get nodes by attribute key
# findAttr(key, val, case, cmp), getElementByAttribute(key, val, case, cmp)	- get nodes by attribute value
SV *
findTag(HTML5::DOM::Node self, SV *key, SV *val = NULL, bool icase = false, SV *cmp = NULL)
ALIAS:
	getElementsByTagName	= 1
	findClass				= 2
	getElementsByClassName	= 3
	findId					= 4
	getElementById			= 5
	findAttr				= 6
	getElementByAttribute	= 7
CODE:
	RETVAL = html5_node_simple_find(cv, self, key, val, cmp, icase, ix);
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

#################################################################
# HTML5::DOM::Encoding
#################################################################
MODULE = HTML5::DOM  PACKAGE = HTML5::DOM::Encoding

SV *
id2name(int id)
CODE:
	size_t len = 0;
	const char *name = myencoding_name_by_id(id, &len);
	RETVAL = name ? newSVpv(name, len) : &PL_sv_undef;
OUTPUT:
	RETVAL

SV *
name2id(SV *text)
CODE:
	text = sv_stringify(text);
	
	STRLEN text_len;
	const char *text_str = SvPV_const(text, text_len);
	
	myencoding_t encoding = MyENCODING_NOT_DETERMINED;
	myencoding_by_name(text_str, text_len, &encoding);
	RETVAL =  encoding != MyENCODING_NOT_DETERMINED ? newSViv(encoding) : &PL_sv_undef;
OUTPUT:
	RETVAL

int
detect(SV *text, size_t max_len = 0)
ALIAS:
	detectByPrescanStream	= 1
	detectRussian			= 2
	detectUnicode			= 3
	detectBom				= 4
CODE:
	text = sv_stringify(text);
	
	STRLEN text_len;
	const char *text_str = SvPV_const(text, text_len);
	
	if (max_len && max_len < text_len)
		text_len = max_len;
	
	myencoding_t encoding;
	
	switch (ix) {
		case 0:
			myencoding_detect(text_str, text_len, &encoding);
		break;
		case 1:
			encoding = myencoding_prescan_stream_to_determine_encoding(text_str, text_len);
		break;
		case 2:
			encoding = myencoding_detect_russian(text_str, text_len, &encoding);
		break;
		case 3:
			encoding = myencoding_detect_unicode(text_str, text_len, &encoding);
		break;
		case 4:
			encoding = myencoding_detect_bom(text_str, text_len, &encoding);
		break;
	}
	
	RETVAL = encoding;
OUTPUT:
	RETVAL
